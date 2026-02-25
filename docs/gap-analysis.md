# LEZ Multisig — Gap Analysis: FURPS vs SPEC vs Implementation

Updated: 2026-02-23

---

## Summary

| Area | Status | Notes |
|------|--------|-------|
| Core M-of-N logic | ✅ Implemented | threshold, members, voting |
| Proposal-as-PDA (Squads-style) | ✅ Implemented | SPEC matches implementation |
| ChainedCall execution | ✅ Implemented | vault auth via pda_seeds |
| PDA derivation | ✅ Implemented | state/proposal/vault all correct |
| Auto-reject when dead | ✅ Implemented | Reject handler handles it |
| Member claiming workaround | ✅ Implemented | Documented in README |
| CLI commands | ✅ Updated | 3-account layout + proposal PDA flow |
| Member management (Add/Remove/ChangeThreshold) | ✅ Implemented | Config change proposals |
| Unit tests | ✅ Complete | All instruction handlers covered |
| E2E test (full flow) | ✅ Implemented | `e2e_tests/` covers full flow |
| README accuracy | ✅ Accurate | |
| SPEC vs implementation | ✅ Matches | No drift detected |
| FURPS vs SPEC | ✅ Aligned | FURPS updated for Squads-style flow |

---

## FURPS vs Implementation

### F1 — Multisig Setup

| Requirement | Status | Notes |
|-------------|--------|-------|
| F1.1: M-of-N threshold (1≤M≤N≤10) | ✅ | Enforced in `create_multisig.rs` |
| F1.2: Members by LEZ public keys | ✅ | `[u8; 32]` AccountIds |
| F1.3: Config in state account | ✅ | `MultisigState` stored as PDA |
| F1.4: Treasury vault PDA | ✅ | `multisig_vault__` PDA derived |
| F1.5: Multiple multisigs via unique `create_key` | ✅ | |

### F2 — Transaction Execution

| Requirement | Status | Notes |
|-------------|--------|-------|
| F2.1: Any member can propose | ✅ | Membership check in propose.rs |
| F2.2: M distinct members must approve | ✅ | `has_threshold()` check in execute.rs |
| F2.3: Any member can execute once threshold met | ✅ | Single ChainedCall tx |
| F2.4: Delegation via ChainedCall | ✅ | Multisig never modifies external state directly |
| F2.5: Native token (λ) transfers | ✅ | Via ChainedCall to token program |

### F3 — Member Management (v0.2)

| Requirement | Status | Notes |
|-------------|--------|-------|
| F3.1: Add member (M sigs required) | ✅ | ProposeAddMember instruction |
| F3.2: Remove member (M sigs required) | ✅ | ProposeRemoveMember + threshold guard |
| F3.3: Change threshold (1≤M≤N guard) | ✅ | ProposeChangeThreshold instruction |

### U1 — CLI Commands

| Command | Status | Notes |
|---------|--------|-------|
| `multisig create` | ✅ | Updated for member PDAs |
| `multisig info` | ✅ | |
| `multisig propose` | ✅ | Proposal PDA flow |
| `multisig approve` | ✅ | |
| `multisig reject` | ✅ | |
| `multisig execute` | ✅ | |
| `multisig add-member` | ✅ | ProposeAddMember config proposal |
| `multisig remove-member` | ✅ | ProposeRemoveMember config proposal |
| `multisig change-threshold` | ✅ | ProposeChangeThreshold config proposal |

### R — Reliability

| Requirement | Status | Notes |
|-------------|--------|-------|
| R1: No funds without M valid approvals | ✅ | `has_threshold()` enforced before execute |
| R2: Nonce-based replay protection | ✅ | LEZ runtime handles nonces |
| R3: Clear error messages | ✅ | `assert!` with descriptive messages throughout |
| R4: Proposals immutable once executed/rejected | ✅ | Status cannot be reversed |

### P — Performance

| Requirement | Status | Notes |
|-------------|--------|-------|
| P1: Single on-chain tx per approve/reject | ✅ | |
| P2: Single on-chain tx for execute (one ChainedCall) | ✅ | |
| P3: O(M) approval checks per execute | ✅ | |

### S — Supportability

| Requirement | Status | Notes |
|-------------|--------|-------|
| S1: Unit tests for all instruction handlers | ✅ | create, propose, approve, reject, execute all covered |
| S2: Integration test (full flow) | ✅ | `e2e_tests/tests/e2e_multisig.rs` |
| S3: SPEC.md documents full account model | ✅ | |
| S4: Gap analysis | ✅ | This document |

---

## SPEC vs Implementation (No Drift)

All account layouts, PDA derivation formulas, and instruction logic in the code match SPEC.md exactly:

- `multisig_state__` tag XOR create_key → ✅ matches `multisig_state_pda_seed()`
- `multisig_prop___` tag XOR create_key XOR index → ✅ matches `proposal_pda_seed()`
- `multisig_vault__` tag XOR create_key → ✅ matches `vault_pda_seed()`
- Account layouts: `[state, signer, proposal]` for Propose/Approve/Reject/Execute → ✅
- Execute: `[state, executor, proposal, ...targets]` → ✅
- Proposer auto-approved → ✅ (`Proposal::new` sets `approved: vec![proposer]`)
- Auto-reject when `remaining_members < threshold` → ✅ in reject.rs
- `ChainedCall` emitted on Execute, not direct transfer → ✅

---

## Remaining Gaps (v0.2 Scope)

### Feature Gaps
1. **CloseProposal**: Reclaim storage from executed/rejected proposals
3. **Time-lock**: Optional delay between threshold reached and execution
4. **Messaging integration**: In-band signing requests via Logos Messaging / Waku

### Nice-to-Have
5. **Batch proposals**: Multiple actions in a single proposal
6. **Proposal expiry**: Auto-expire stale proposals after configurable timeout
