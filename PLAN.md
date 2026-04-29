# Contracts — Development Plan

Scope: three Solidity contracts that together form the Bulletin Board for the
Munich Personalratswahl prototype. Voting SDK, Vote Proxy, Wahlregister and
Keycloak are out of scope.

## 1. Contract layout

| Contract            | Role                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------ |
| `ElectionRegistry`  | Admin-gated factory + index of `Election` instances. Holds `VOTE_MANAGER` admin role.      |
| `KeyperSet`         | Near-1:1 port of `shutter-network/contracts/src/common/KeyperSet.sol`. Membership + threshold + finalize flag. One per election (or reusable). |
| `Election`          | Per-election state machine: config, DKG voting, ballots, decryption shares, result.        |

No proxies, no upgradability. Elections are immutable after finalization.

## 2. Toolchain

- Foundry (`forge`, `cast`, `anvil`).
- Solidity `^0.8.24`.
- OpenZeppelin Contracts v5 (`AccessControl`, `Pausable`, `ReentrancyGuard` where justified).
- Target chain: Gnosis Chain. No CI yet.

## 3. Data types

- G1 points: `bytes` (length check == 48, compressed).
- G2 points: `bytes` (length check == 96, compressed).
- Scalars (Fiat-Shamir `e`, responses `z`): `uint256` (implicit mod q off-chain).
- `struct DLEQProof { uint256 e; uint256 z; }`
- Ciphertext: `struct Ciphertext { bytes c1; bytes c2; }` (both G2, 96 bytes).
- No on-chain pairing checks. No on-curve check beyond length; Tally Aggregator is responsible for full validation.

## 4. Access control (OpenZeppelin `AccessControl`)

- `DEFAULT_ADMIN_ROLE` — Vote Manager. Creates elections, registers keyper sets, sets phases, halts.
- `VOTE_PROXY_ROLE` — fee waiver on `submitVote` only. Does **not** gate who can vote.
- `TALLY_AGGREGATOR_ROLE` — authorized to publish final tally + combined decryption output.
- Keyper identity is not a role; it is implicit via `KeyperSet.isMember(msg.sender)` at the election's configured keyper set.

## 5. Phase gating

- Phases derived from `block.timestamp` crossed with artefact presence (e.g. DKG finalized, tally published).
- No cron, no automatic transitions beyond what timestamps and state imply.
- Transitions are one-way; `VOTE_MANAGER` can only abort, never rewind.

## 6. DKG publication (Shutter-style on-chain voting)

Each keyper k independently calls:

```solidity
voteDKGResult(
    bytes  pkElection,        // aggregated election public key (G2, 96B)
    bytes[] committeePKs      // all n individual committee PKs, sorted by keyper index
)
```

Contract behaviour:

- Requires `KeyperSet.isMember(msg.sender)` and keyper has not voted yet.
- Computes `digest = keccak256(abi.encode(pkElection, committeePKs))`.
- Increments `votesFor[digest]`; sets `hasVoted[msg.sender] = true`.
- Emits `DKGVoteRegistered(keyper, pkElection)`.
- When `votesFor[digest] >= threshold`, stores `(pkElection, committeePKs)` once,
  emits `DKGResultPublished(pkElection, committeePKs)`, locks DKG phase.
- Subsequent duplicate votes revert with `AlreadyFinalized`.

Ordering requirement:

- Every keyper must submit `committeePKs` sorted by immutable keyper index from the election's `KeyperSet`.
- `committeePKs[i]` must be the public key for `keyperSet.getMember(i)`.
- A keyper can read its own index with `keyperSet.getMemberIndex(keyperAddress)`.
- Mismatched ordering changes the DKG result digest and therefore votes for a different result.

All n committee PKs are published together in the single winning tally. Any
keyper-selection / Lagrange math is performed off-chain by the Tally Aggregator
using `committeePKs` as public reference.

## 7. Ballots

Entrypoint (anyone can call):

```solidity
submitVote(
    bytes pseudonym,                 // opaque voter handle from Wahlregister
    Ciphertext[] ciphertexts,        // one per candidate (or per bit for Variant B)
    DLEQProof[][] rangeProofs,       // B+1 branches (Variant A) or 2 branches (Variant B)
    DLEQProof budgetProof
)
```

Rules:

- Public function. No allow-list of callers.
- `VOTE_PROXY_ROLE` holders get a fee waiver (gas-refund / zero-fee path). All other callers pay gas normally.
- All ballots appended to storage; emit `VoteSubmitted(pseudonym, ballotIndex)`.
- **No `REPLACED` marking.** Re-votes are stored verbatim; Tally Aggregator selects the latest ballot per pseudonym by `ballotIndex` / `block.number`.
- No on-chain proof verification. Tally Aggregator verifies all proofs off-chain before aggregating.

## 8. Decryption shares + result

- Each keyper calls `submitDecryptionShare(bytes sigma, DLEQProof proof)` after voting ends.
- Contract stores verbatim; emits `DecryptionSharePosted(keyper)`.
- `TALLY_AGGREGATOR_ROLE` calls `finalizeResult(uint256[] candidateTotals, bytes combinedSigma)` once it has combined t+1 valid shares off-chain.
- Emits `ResultFinalized`; election becomes immutable.

## 9. Events (minimum set)

- `ElectionCreated(address election, uint256 electionId)`
- `DKGVoteRegistered(address keyper, bytes pkElection)`
- `DKGResultPublished(bytes pkElection, bytes[] committeePKs)`
- `VoteSubmitted(bytes pseudonym, uint256 ballotIndex)`
- `DecryptionSharePosted(address keyper)`
- `ResultFinalized(uint256[] totals)`

## 10. Python-side changes (follow-up, not blocking contract work)

1. Add compressed point codecs to `src/crypto/primitives.py` (G1=48B, G2=96B) to match Solidity payloads; keep existing `point_to_dict` for debug only.
2. New module `src/eth_client.py` wrapping `web3.py`: read/write helpers for `ElectionRegistry`, `KeyperSet`, `Election`.
3. Rewire `src/keyper.py`:
   - Replace Flask P2P DKG orchestration with on-chain `voteDKGResult` publication.
   - Replace HTTP `/decrypt` with on-chain `submitDecryptionShare`.
4. Split `src/backend.py` tally path into a standalone `src/tally_aggregator.py` service that:
   - Reads ballots + shares from chain.
   - Verifies all ZK proofs (range, budget, decryption).
   - Selects latest ballot per pseudonym.
   - Reassembles Variant B binary decompositions if used.
   - Calls `finalizeResult`.

## 11. Build order

1. Foundry project scaffold (`forge init`, remappings for OZ).
2. Port `KeyperSet.sol` (minimal changes; keep Shutter semantics).
3. `ElectionRegistry.sol` skeleton + roles + `createElection`.
4. `Election.sol` — config + DKG voting path first; one Foundry test for threshold-triggered finalization.
5. `Election.sol` — ballots path; Foundry tests for public submit + proxy fee waiver.
6. `Election.sol` — decryption shares + `finalizeResult`; Foundry test for full e2e happy path.
7. Python integration: compressed codec → `eth_client.py` → rewire `keyper.py` → split out `tally_aggregator.py`.
8. End-to-end demo: DKG → voting → tally → result on local `anvil`, then Gnosis Chiado testnet.

## 12. Out of scope (explicit)

- Voting SDK — other team.
- Vote Proxy service — other team; this repo only grants it `VOTE_PROXY_ROLE`.
- Wahlregister-Server pseudonymization.
- Keycloak / OIDC.
- On-chain pairing or proof verification.
- Contract upgradability.
