# Urban Verified: Bulletin Board (Smart Contracts)

> **Part of the Urban Verified: Private and Verifiable Online Voting stack.**
> To understand the full end-to-end architecture, start with the [thresholdELGamal README](https://github.com/Urban-Verified/thresholdELGamal#readme).

This repository contains the Foundry smart contracts that act as the public **bulletin board** of an election. Everything that has to be public and tamper-proof is written here: the election setup, the election public key, every encrypted ballot, the encrypted total, the keypers' decryption shares and the final result.

## Where this fits

The contracts are the single shared record that every other part of the system reads from and writes to. They store data and enforce who may write what and when; they do **not** check the cryptographic proofs. Proof checking happens off-chain in the tally aggregator and in the Voting Dashboard, and anyone can repeat it from the data stored here.

```
  Election admin ─── publishElection ──────────────────>  ┌──────────────────────┐
  Keypers ────────── voteDKGResult ────────────────────>  │                      │
  Vote proxy ─────── submitVote (encrypted ballots) ───>  │   ElectionRegistry   │
  Tally aggregator ─ publishAggregate, publishResult ──>  │   + Election         │
  Keypers ────────── submitDecryptionShare ────────────>  │   + KeyperSet        │
                                                          │                      │
  Tally aggregator, Voting Dashboard, anyone  <── read ─  │                      │
                                                          └──────────────────────┘
```

| Who | Writes | Reads |
|---|---|---|
| Election admin | New elections via `ElectionRegistry.publishElection` | |
| Keypers ([thresholdELGamal](https://github.com/Urban-Verified/thresholdELGamal)) | DKG result vote, decryption shares | Election config, encrypted total |
| Vote proxy | Encrypted ballots (`submitVote`) | |
| Tally aggregator ([thresholdELGamal](https://github.com/Urban-Verified/thresholdELGamal)) | Encrypted total, final result | Ballots and their proofs, decryption shares |
| [Voting Dashboard](https://github.com/Urban-Verified/voting-dashboard) and anyone | | Everything |

The `pkWR` field in each election is the public key of the **Voter Registry Oracle** (*Wahlregister*), the service that confirms a voter is eligible. Every ballot carries its signed attestation.

The contract ABIs are copied into [`thresholdELGamal/abis`](https://github.com/Urban-Verified/thresholdELGamal/tree/main/abis). When a contract interface changes here, those ABIs must be refreshed too.

### Related repositories

| Repository | Role |
|---|---|
| [`thresholdELGamal`](https://github.com/Urban-Verified/thresholdELGamal) | Keypers, DKG coordinator, tally aggregator. Entry point for the whole system |
| [`shutter-voting-sdk`](https://github.com/Urban-Verified/shutter-voting-sdk) | TypeScript SDK that builds and verifies encrypted ballots (`@shutter-network/urban-verified-crypto`) |
| [`voting-dashboard`](https://github.com/Urban-Verified/voting-dashboard) | Read-only website that follows and verifies each election |

## Contract scope

The contract scope covers:

- `KeyperSet` immutable membership and threshold configuration
- `ElectionRegistry` deployment and indexing of elections
- `Election` DKG result publication
- ballot submission (proof hash stored on chain, full proof emitted in the `VoteSubmitted` event)
- decryption share submission
- tally finalization
- fee withdrawal by the admin
- stable interfaces for integration
- deployment script and test coverage

## Repository Layout

### Core contracts

- `src/KeyperSet.sol`
- `src/ElectionRegistry.sol`
- `src/Election.sol`
- `src/election/ElectionBase.sol`
- `src/election/ElectionDKG.sol`
- `src/election/ElectionVoting.sol`
- `src/election/ElectionTally.sol`
- `src/election/ElectionDecryption.sol`
- `src/election/ElectionAdmin.sol`
- `src/VotingTypes.sol`

### Interfaces

- `src/interfaces/IKeyperSet.sol`
- `src/interfaces/IElection.sol`
- `src/interfaces/IElectionRegistry.sol`

### Scripts

- `script/Deploy.s.sol`
- `script/DeployAndPublishLocal.s.sol`
- `script/PublishElection.s.sol`

### Tests

- `test/Scaffold.t.sol`
- `test/KeyperSet.t.sol`
- `test/ElectionRegistry.t.sol`
- `test/ElectionDKG.t.sol`
- `test/ElectionVote.t.sol`
- `test/ElectionTally.t.sol`
- `test/ElectionAdmin.t.sol`
- `test/ElectionInvariant.t.sol`
- `test/BallotProofStorage.t.sol`

## Contract Overview

### `KeyperSet`

`KeyperSet` is the immutable keyper committee contract. It is used by elections to determine membership and threshold.

Implemented behavior:

- constructor-time member and threshold configuration
- duplicate member rejection
- zero-address rejection
- threshold validation
- getters and membership checks

Available read methods include:

- `getNumMembers`
- `getMember`
- `getMembers`
- `getMemberIndex`
- `getThreshold`
- `isMember`

### `ElectionRegistry`

`ElectionRegistry` is the admin-gated factory and index for `Election` instances.

Implemented behavior:

- `DEFAULT_ADMIN_ROLE`-gated `publishElection`
- sequential `electionId` assignment
- address lookup by election id
- paged lookup through `getElections`
- `ElectionCreated` event emission

`publishElection` validates that the supplied `KeyperSet` is:

- non-empty
- configured with a non-zero threshold no greater than the keyper count

### `Election`

`Election` is the per-election bulletin board contract.

Immutable election configuration:

- `electionId`
- `keyperSet`
- `votingStart`
- `votingEnd`
- `selfSubmitFee`
- `numCandidates`
- `budget`
- `pkWR` (public key of the Voter Registry Oracle)

Configured roles:

- `DEFAULT_ADMIN_ROLE`
- `TALLY_AGGREGATOR_ROLE`
- `VOTE_PROXY_ROLE`

#### DKG result publication

Implemented behavior:

- `voteDKGResult(bytes pkElection, bytes[] committeePKs)`
- keyper-only participation
- one DKG vote per keyper
- votes are counted by `keccak256(abi.encode(pkElection, committeePKs))`
- different DKG results can receive votes independently
- finalization once one DKG result reaches the keyper threshold
- storage of the finalized election public key
- storage of finalized committee public keys
- `DKGVoteRegistered` includes the voting keyper and submitted `pkElection`
- `DKGResultPublished` includes the finalized `pkElection` and committee public keys

Ordering requirement:

- every keyper must submit `committeePKs` sorted by the immutable keyper indices from the election's `KeyperSet`
- `committeePKs[i]` must be the public key for `keyperSet.getMember(i)`
- a keyper can read its own index with `keyperSet.getMemberIndex(keyperAddress)`
- `committeePKs` ordering is part of the DKG result digest, so mismatched ordering votes for a different result

Read helpers:

- `isDKGFinalized`
- `getElection`

Validation:

- election public key must be 96-byte compressed G2 bytes
- each committee public key must be 96-byte compressed G2 bytes
- committee public key count must match keyper count

#### Ballot submission

Implemented behavior:

- public `submitVote(Ballot)`
- self-submit fee enforcement
- fee waiver for callers with `VOTE_PROXY_ROLE`
- append-only ballot storage; a re-vote appends a new record, and `getBallot(pseudonym)` returns the newest one
- on-chain storage of:
  - pseudonym
  - voter verification key
  - timestamp
  - submitting address
  - ciphertexts
  - keccak256 hash of the ballot proof (`zkProofHash`)
  - voter signature
  - WR attestation
- the full ballot proof bytes are emitted in `VoteSubmitted(pseudonym, ballotIndex, zkProof)` instead of being stored, which keeps large ballots under the block gas limit. Readers recover the proof from the event log and check it against `zkProofHash`

Read helpers:

- `getNumBallots`
- `getBallot(bytes32 pseudonym)`
- `getBallots`
- `getElection`
- `getPhase`

Validation:

- DKG must be finalized
- voting must be within the configured time window
- pseudonym must be non-zero
- voter verification key must be a 48-byte compressed G1 point
- ciphertext count must equal `numCandidates`
- proof bytes must be present
- voter signature bytes must be present
- WR attestation bytes must be present
- each ciphertext point must be 96-byte compressed G2 bytes
- `msg.value` must match the expected fee rule exactly

#### Decryption share submission

Implemented behavior:

- `submitDecryptionShare(bytes[] shares, DLEQProof[] proofs)`
- one share bundle per keyper
- on-chain storage of one share per candidate
- on-chain storage of one proof per candidate
- storage of the publishing keyper index

Read helpers:

- `getDecryptionShares`

Validation:

- DKG must be finalized
- voting must already be closed
- caller must be a keyper
- caller may only submit once
- `shares.length` must equal `numCandidates`
- `proofs.length` must equal `numCandidates`
- each share must be a 96-byte compressed G2 point

#### Aggregate publication

Implemented behavior:

- `publishAggregate(EncryptedTally)`
- restricted to `TALLY_AGGREGATOR_ROLE`
- aggregate ciphertext storage
- a later call replaces the stored aggregate

Read helpers:

- `getAggregate`

Validation:

- DKG must be finalized
- voting must already be closed
- aggregate ciphertext count must equal `numCandidates`
- each aggregate ciphertext point must be 96-byte compressed G2 bytes

#### Final result publication

Implemented behavior:

- `publishResult(uint256[] totals, uint8[] keyperIndices)`
- restricted to `TALLY_AGGREGATOR_ROLE`
- storage of final totals
- storage of the keyper indices used for the tally
- later publications overwrite the stored result

Read helpers:

- `isResultFinalized`
- `getResult`

Validation:

- DKG must be finalized
- voting must already be closed
- totals length must match `numCandidates`
- `keyperIndices` must be non-empty

#### Fee withdrawal

Implemented behavior:

- `withdrawFees(address payable recipient)`
- restricted to `DEFAULT_ADMIN_ROLE`
- `FeesWithdrawn` event emission
- direct ETH transfers rejected through `receive` and `fallback`

Validation:

- recipient must be non-zero
- failed ETH transfer reverts

## Shared Types

`src/VotingTypes.sol` defines the shared structs used across contract boundaries:

- `ElectionParams`
- `DLEQProof`
- `Ciphertext`
- `Ballot`
- `BallotRecord`
- `BallotView`
- `DKGResult`
- `ElectionConfigView`
- `EncryptedTally`
- `DecryptionShare`
- `ElectionResult`

All curve-related values are stored as raw `bytes` in contract storage.

## Stable Interfaces

The integration surface is exposed through:

- `IKeyperSet`
- `IElection`
- `IElectionRegistry`

These interfaces include:

- events
- external getters
- query helpers

## Finalized Design Decisions

The following decisions are already encoded in the contract implementation:

- duplicate keypers are not allowed
- elections can only be created from non-empty keyper sets with a valid threshold
- DKG publication uses threshold voting by full result digest, so the first keyper cannot pin the canonical result
- DKG committee public keys must be sorted by keyper index; use `KeyperSet.getMemberIndex(address)` to map a keyper address to its index
- voter signatures and WR attestations are stored on-chain; ballot proofs are stored as a keccak256 hash, with the full bytes in the `VoteSubmitted` event
- WR public key is part of election configuration
- curve points are stored as `bytes`
- `submitVote` is public
- the fee waiver applies to the contract fee, not gas costs
- revotes are appended as new ballots
- one decryption-share bundle is stored per keyper, with one share and one proof per candidate
- collected fees can be withdrawn by `DEFAULT_ADMIN_ROLE` at any time
- no on-chain pairing verification is performed

## Deployment Scripts

### `script/Deploy.s.sol`

`Deploy.s.sol` is the generic deployment script for any Foundry-supported network.

It:

- deploys `KeyperSet`
- deploys `ElectionRegistry`
- logs deployed addresses after broadcast

It does **not** publish an election. Use `script/PublishElection.s.sol` to create elections on top of an existing deployment.

Supported environment variables:

- `PRIVATE_KEY` (required): the deployer key that broadcasts the transactions
- `VOTE_MANAGER`: registry admin; defaults to the `PRIVATE_KEY` address if unset
- `KEYPERS` as a comma-separated list of keyper addresses
- or `KEYPER_COUNT` plus `KEYPER_1`, `KEYPER_2`, ... `KEYPER_N`
- `KEYPER_THRESHOLD`

If `KEYPER_THRESHOLD` is unset, it defaults to the full keyper count.

Example:

```shell
export PRIVATE_KEY=...
export KEYPERS=0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222,0x3333333333333333333333333333333333333333
export KEYPER_THRESHOLD=2

forge script script/Deploy.s.sol:DeployScript --rpc-url <RPC_URL> --broadcast
```

### `script/PublishElection.s.sol`

`PublishElection.s.sol` publishes (deploys) a new `Election` via an **existing**
`ElectionRegistry` and **existing** `KeyperSet`.

It calls:

- `ElectionRegistry.publishElection(IKeyperSet keyperSet, VotingTypes.ElectionParams params)`

Required environment variables (suitable for a `.env` file):

- `PRIVATE_KEY`: admin private key (must have `DEFAULT_ADMIN_ROLE` on the registry)
- `REGISTRY`: deployed `ElectionRegistry` address
- `KEYPER_SET`: deployed `KeyperSet` address
- `VOTING_START`: unix timestamp (seconds)
- `VOTING_END`: unix timestamp (seconds)
- `SELF_SUBMIT_FEE`: fee in wei for direct `submitVote` (set `0` if unused)
- `NUM_CANDIDATES`: number of candidates
- `BUDGET`: max selections / per-ballot budget parameter
- `PK_WR`: public key of the Voter Registry Oracle (a compressed G1 point, 48 bytes, e.g. `0x...`; the length is not checked on chain)
- `TALLY_AGGREGATOR`: address that will hold `TALLY_AGGREGATOR_ROLE`
- `VOTE_PROXY`: address that will hold `VOTE_PROXY_ROLE`

Example `.env`:

```shell
PRIVATE_KEY=0x...
REGISTRY=0x...
KEYPER_SET=0x...

VOTING_START=1715000000
VOTING_END=1715003600
SELF_SUBMIT_FEE=0
NUM_CANDIDATES=2
BUDGET=1
PK_WR=0x...
TALLY_AGGREGATOR=0x...
VOTE_PROXY=0x...
```

Run:

```shell
set -a
source .env
set +a

forge script script/PublishElection.s.sol:PublishElection --rpc-url <RPC_URL> --broadcast
```

### `script/DeployAndPublishLocal.s.sol`

`DeployAndPublishLocal.s.sol` is a small local/demo bootstrap helper.

It deploys and publishes in one run:

- `KeyperSet` with 2 keypers (`KEYPER_1`, `KEYPER_2`) and threshold 2
- `ElectionRegistry`
- an initial `Election` via `ElectionRegistry.publishElection` (with quick defaults)

```shell
forge script script/DeployAndPublishLocal.s.sol:DeployAndPublishLocalScript --rpc-url http://127.0.0.1:8545 --broadcast
```

Before running it, note that the defaults do not work on their own:

- set `KEYPER_1` and `KEYPER_2` to two different addresses. Both default to the admin, and `KeyperSet` rejects duplicates
- leave `VOTE_MANAGER` unset or set it to the broadcasting address, because only the registry admin can publish the election
- set `PK_WR`, which defaults to empty bytes

This script is meant for local demo flows only. For real deployments, use:

- `script/Deploy.s.sol` (deploy once)
- `script/PublishElection.s.sol` (publish elections many times)

## Validation

The contract package is covered by unit tests and invariant tests.

Test coverage includes:

- scaffold deployment
- keyper set construction and validation
- registry creation and validation rules
- DKG threshold voting
- ballot submission and reads
- decryption share submission and reads
- result finalization
- fee withdrawal
- stateful invariants for ballot count, share count, and fee balance

Validated commands:

```shell
forge build
forge test
```

At the time of writing, the full suite passes.

## Notes

- `getPhase()` returns `0` (waiting for DKG), `2` (DKG finalized, before voting), `3` (voting open) or `4` (voting closed). There is no phase `1` because the election config has no separate registration boundary. Whether the result is published is read with `isResultFinalized()`.
- `forge build` uses `via_ir = true` in `foundry.toml` because `getElection()` returns nested structs and otherwise hits Solidity stack-depth limits.

## Quick Commands

```shell
forge build
forge test
forge fmt
forge script script/Deploy.s.sol:DeployScript --rpc-url <RPC_URL> --broadcast
```

---

## Licence

Copyright (C) 2026 Brainbot GmbH

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License, version 3 only, as published
by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>.

SPDX-License-Identifier: AGPL-3.0-only
