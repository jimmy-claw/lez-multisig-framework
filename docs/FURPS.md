# Multisig PoC — FURPS Specification

> **Status:** Draft — 2026-02-16 (updated 2026-02-21)
> **Scope:** Public mode only, basic M-of-N threshold
> **Target:** LEZ Testnet

---

## Functionality (F)

### F1. Multisig Setup
- **F1.1**: Create multisig with M-of-N threshold (M ≤ N, 1 ≤ M ≤ 5, N ≤ 10 for PoC)
- **F1.2**: Members identified by LEZ public keys (AccountIds, 32 bytes)
- **F1.3**: Configuration stored in multisig state account (PDA)
- **F1.4**: Multisig owns a treasury vault (PDA, derived from create_key)
- **F1.5**: Multiple independent multisigs supported per program via unique `create_key`

### F2. Transaction Execution (Squads-style async flow)
- **F2.1**: Any member can propose a transaction — creates a Proposal PDA account
- **F2.2**: M distinct members must each approve in their own separate on-chain transactions
- **F2.3**: Once M approvals are collected, any member can execute the proposal in a single transaction
- **F2.4**: Execution delegates via NSSA `ChainedCall` to the target program — the multisig never modifies external state directly
- **F2.5**: Support native token (λ) transfers via ChainedCall to token program

### F3. Member Management *(not yet implemented — post-PoC)*
- **F3.1**: Add member (requires M current signatures)
- **F3.2**: Remove member (requires M current signatures)
- **F3.3**: Change threshold (requires M current signatures, must satisfy 1 ≤ M ≤ N)

---

## Usability (U)

### U1. CLI Commands *(partially implemented — needs update for proposal PDA flow)*
```
# Create 2-of-3 multisig
lez-wallet multisig create --threshold 2 --member <pk1> --member <pk2> --member <pk3>

# View multisig info
lez-wallet multisig info --account <multisig_id>

# Propose transfer (creates proposal PDA on-chain)
lez-wallet multisig propose --multisig <id> --to <recipient> --amount 100

# Approve proposal (each member in their own tx)
lez-wallet multisig approve --multisig <id> --proposal <index>

# Reject proposal
lez-wallet multisig reject --multisig <id> --proposal <index>

# Execute once threshold is met
lez-wallet multisig execute --multisig <id> --proposal <index>

# Add member (post-PoC)
lez-wallet multisig add-member --multisig <id> --member <new_pk>

# Remove member (post-PoC)
lez-wallet multisig remove-member --multisig <id> --member <pk>
```

---

## Reliability (R)

- **R1**: No funds move without M valid approvals from distinct members
- **R2**: Nonce-based replay protection (handled by NSSA runtime)
- **R3**: Clear error messages for insufficient approvals, invalid members, wrong proposal state
- **R4**: Proposals are immutable once executed or rejected — status cannot be reversed

---

## Performance (P)

- **P1**: Each approve/reject is a single on-chain transaction
- **P2**: Execute is a single on-chain transaction emitting one ChainedCall
- **P3**: O(M) approval checks per execute

---

## Supportability (S)

- **S1**: Unit tests for all instruction handlers
- **S2**: Integration test: create → fund → propose → approve → execute → verify balances
- **S3**: SPEC.md documents full account model, PDA derivation, instruction set, validation rules
- **S4**: Gap analysis in docs/gap-analysis.md

---

## Architecture Notes

### Squads-style On-Chain Proposals

Unlike traditional offline multisig (collect N signatures, broadcast once), this implementation stores each proposal as a separate PDA account on-chain. Members approve asynchronously — no coordination required. This means:

- No offline signature collection
- Any member can check proposal status at any time
- Members can approve/reject independently from any wallet

### ChainedCall Execution Model

The multisig acts as a **governance wrapper**, not an executor. On Execute:
1. Multisig verifies approvals ≥ threshold
2. Multisig emits a `ChainedCall` to the target program
3. The target program (e.g., token program) performs the actual action

This ensures the multisig program has minimal surface area and cannot directly modify arbitrary external state.

### Member Account Claiming

Due to NSSA runtime validation rules, member accounts must be **fresh keypairs** dedicated to each multisig. During `CreateMultisig`, all member accounts are claimed by the multisig program. See [LSSA issue #339](https://github.com/logos-blockchain/lssa/issues/339) for context.

---

## Known Limitations (PoC Scope)

- Member management (F3) not yet implemented
- CLI needs update for proposal PDA flow
- No `CloseProposal` to reclaim executed/rejected proposal storage
- No time-lock between threshold reached and execution
