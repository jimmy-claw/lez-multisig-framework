# LEZ Multisig — Technical Specification

## Overview

An M-of-N multisig governance program for the NSSA runtime, inspired by [Squads Protocol v4](https://docs.squads.so/). The multisig collects approvals from members and executes actions on other programs via NSSA ChainedCalls.

**Key principle:** The multisig never directly modifies external state. It only manages proposals and voting, then delegates execution via `ChainedCall`.

---

## Account Model

The program uses three types of on-chain accounts, all derived as PDAs from the program ID:

| Account | Purpose | Lifecycle | Owner |
|---------|---------|-----------|-------|
| **Multisig State** | Stores config: members, threshold, tx counter | Created once, updated on Propose (counter++) | Multisig program |
| **Proposal** | Stores a single proposal: action params + voting state | Created on Propose, updated on Approve/Reject/Execute | Multisig program |
| **Vault** | Holds assets controlled by the multisig | Created on first use (e.g., token transfer to vault PDA) | Target program (e.g., token program) |

### Multisig State Account

```rust
struct MultisigState {
    create_key: [u8; 32],      // Unique key for this multisig instance
    threshold: u8,              // Required approvals (M)
    member_count: u8,           // Total members (N)
    members: Vec<[u8; 32]>,    // Member AccountIds
    transaction_index: u64,     // Monotonic counter, incremented on each Propose
}
```

### Proposal Account

```rust
struct Proposal {
    index: u64,                          // Matches transaction_index at creation
    proposer: [u8; 32],                  // Who created it
    multisig_create_key: [u8; 32],       // Parent multisig (for verification)

    // ChainedCall parameters
    target_program_id: ProgramId,        // Program to call on Execute
    target_instruction_data: Vec<u32>,   // Serialized instruction for target
    target_account_count: u8,            // Expected target accounts at execute time
    pda_seeds: Vec<[u8; 32]>,           // PDA seeds for authorization
    authorized_indices: Vec<u8>,         // Which target accounts get is_authorized=true

    // Voting state
    approved: Vec<[u8; 32]>,            // Members who approved (proposer auto-included)
    rejected: Vec<[u8; 32]>,            // Members who rejected
    status: ProposalStatus,              // Active | Executed | Rejected | Cancelled
}
```

---

## PDA Derivation

All PDAs follow the NSSA standard: `AccountId = SHA256(prefix ‖ program_id ‖ seed)` where prefix is the 32-byte constant `"/NSSA/v0.2/AccountId/PDA/\x00\x00\x00\x00\x00\x00\x00"`.

### Multisig State PDA

```
tag  = "multisig_state__"            (16 bytes, padded to 32 with 0x00)
seed = tag XOR create_key            (32 bytes)
PDA  = NSSA_PDA(program_id, seed)
```

### Proposal PDA

```
tag  = "multisig_prop___"            (16 bytes, padded to 32 with 0x00)
seed = tag XOR create_key            (32 bytes)
seed[24..32] ^= proposal_index      (big-endian u64, XOR'd into last 8 bytes)
PDA  = NSSA_PDA(program_id, seed)
```

### Vault PDA

```
tag  = "multisig_vault__"            (16 bytes, padded to 32 with 0x00)
seed = tag XOR create_key            (32 bytes)
PDA  = NSSA_PDA(program_id, seed)
```

### Properties

- **Deterministic**: Anyone can compute any PDA given `program_id` and `create_key` (+ `proposal_index` for proposals)
- **Collision-free**: Different tags ensure state/proposal/vault PDAs never collide
- **Multi-instance**: Different `create_key` values create independent multisigs under the same program

---

## Instructions

### CreateMultisig

Creates a new multisig instance.

| Field | Type | Description |
|-------|------|-------------|
| `create_key` | `[u8; 32]` | Unique key (typically random) |
| `threshold` | `u8` | Required approvals (1 ≤ M ≤ N ≤ 10) |
| `members` | `Vec<[u8; 32]>` | Member AccountIds |

**Accounts:**

| # | Account | Auth | Constraint |
|---|---------|------|------------|
| 0 | Multisig State PDA | — | Must be `Account::default()` (uninitialized) |

**Effects:** Initializes MultisigState, claims account ownership.

---

### Propose

Creates a new proposal to execute a ChainedCall.

| Field | Type | Description |
|-------|------|-------------|
| `target_program_id` | `ProgramId` | Program to call |
| `target_instruction_data` | `Vec<u32>` | Serialized instruction |
| `target_account_count` | `u8` | Number of target accounts at execute time |
| `pda_seeds` | `Vec<[u8; 32]>` | PDA seeds for chained call authorization |
| `authorized_indices` | `Vec<u8>` | Which target accounts get `is_authorized=true` |

**Accounts:**

| # | Account | Auth | Constraint |
|---|---------|------|------------|
| 0 | Multisig State PDA | — | Existing, deserialized for membership check |
| 1 | Proposer | ✅ signer | Must be a member |
| 2 | Proposal PDA | — | Must be `Account::default()` (uninitialized) |

**Effects:**
- Increments `MultisigState.transaction_index`
- Creates Proposal with proposer auto-approved
- Claims proposal account ownership

---

### Approve

Adds a member's approval to an existing proposal.

| Field | Type | Description |
|-------|------|-------------|
| `proposal_index` | `u64` | Which proposal to approve |

**Accounts:**

| # | Account | Auth | Constraint |
|---|---------|------|------------|
| 0 | Multisig State PDA | — | Existing, for membership check |
| 1 | Approver | ✅ signer | Must be a member, not already approved |
| 2 | Proposal PDA | — | Must belong to this multisig, status = Active |

**Effects:** Adds approver to `proposal.approved`. Removes from `rejected` if previously rejected.

---

### Reject

Adds a member's rejection to an existing proposal.

| Field | Type | Description |
|-------|------|-------------|
| `proposal_index` | `u64` | Which proposal to reject |

**Accounts:**

| # | Account | Auth | Constraint |
|---|---------|------|------------|
| 0 | Multisig State PDA | — | Existing, for membership/threshold check |
| 1 | Rejector | ✅ signer | Must be a member, not already rejected |
| 2 | Proposal PDA | — | Must belong to this multisig, status = Active |

**Effects:** Adds rejector to `proposal.rejected`. If proposal can never reach threshold (`remaining_members < threshold`), auto-sets status to `Rejected`.

---

### Execute

Executes a fully-approved proposal by emitting a ChainedCall.

| Field | Type | Description |
|-------|------|-------------|
| `proposal_index` | `u64` | Which proposal to execute |

**Accounts:**

| # | Account | Auth | Constraint |
|---|---------|------|------------|
| 0 | Multisig State PDA | — | Existing, for threshold verification |
| 1 | Executor | ✅ signer | Must be a member |
| 2 | Proposal PDA | — | Status = Active, `approved.len() >= threshold` |
| 3.. | Target accounts | — | Count must match `proposal.target_account_count` |

**Effects:**
- Sets proposal status to `Executed`
- Emits `ChainedCall` to `proposal.target_program_id` with:
  - `instruction_data` from proposal
  - `pre_states` = target accounts (with `is_authorized` set per `authorized_indices`)
  - `pda_seeds` from proposal (proves multisig's PDA authority to target program)

---

## Transaction Flow

```
                    ┌─────────────┐
                    │ CreateMultisig │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
            ┌───── │   Propose    │ ◄── any member
            │      └──────┬──────┘
            │             │ (auto-approves proposer)
            │      ┌──────▼──────┐
            │      │   Approve   │ ◄── other members (repeat until M reached)
            │      └──────┬──────┘
            │             │
            │      ┌──────▼──────┐
            │      │   Execute   │ ◄── any member (when threshold met)
            │      └──────┬──────┘
            │             │
            │      ┌──────▼──────┐
            │      │ ChainedCall │ ──► target program (e.g., token transfer)
            │      └─────────────┘
            │
            │      ┌─────────────┐
            └───── │   Reject    │ ◄── any member (can kill proposal)
                   └─────────────┘
```

### Example: Transfer tokens from multisig vault

1. **Propose**: Member creates proposal targeting the token program's `Transfer` instruction, with vault PDA seed in `pda_seeds` and vault account index in `authorized_indices`
2. **Approve**: Second member approves (for 2-of-3)
3. **Execute**: Any member executes. Multisig emits `ChainedCall` to token program with vault account marked `is_authorized=true`. Token program sees the vault as authorized (via PDA verification) and executes the transfer.

---

## Validation Rules

The NSSA runtime enforces these rules on every transaction:

1. Pre/post state arrays must have equal length
2. All account IDs must be unique
3. Nonce must not change
4. `program_owner` must not change
5. Balance decrease only allowed on accounts owned by executing program
6. Data changes only allowed on accounts owned by executing program OR uninitialized (`Account::default()`)
7. Total balance must be preserved across all accounts

---

## Future Considerations

- **Account cleanup**: Executed/rejected proposals remain on-chain. Consider a `CloseProposal` instruction to reclaim storage.
- **Config changes**: `AddMember`, `RemoveMember`, `ChangeThreshold` instructions (not yet implemented).
- **Time-lock**: Optional delay between reaching threshold and execution.
- **Multiple vaults**: Different vault PDAs per asset type.
- **GitHub Actions CI**: Automated testing on PR push.
