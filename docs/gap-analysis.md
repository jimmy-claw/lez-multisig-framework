# LEZ Multisig — Gap Analysis: FURPS vs SPEC vs README vs Implementation

Generated: 2026-02-21

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
| CLI commands | ❌ Not updated | Old 2-account layout, known issue |
| Member management (Add/Remove/ChangeThreshold) | ❌ Not implemented | FURPS F3, SPEC future work |
| Unit tests | ⚠️ Partial | approve/reject have tests; create/propose/execute do not |
| E2E test (full flow) | ✅ Implemented | `e2e_tests/` covers full flow |
| README accuracy | ✅ Mostly accurate | One minor mismatch (see below) |
| SPEC vs implementation | ✅ Matches | No drift detected |
| FURPS vs SPEC | ⚠️ Some gaps | FURPS is older, SPEC evolved beyond it |

---

## FURPS vs Implementation

### F1 — Multisig Setup

| Requirement | Status | Notes |
|-------------|--------|-------|
| F1.1: M-of-N threshold (1≤M≤N≤10) | ✅ | Enforced in `create_multisig.rs` |
| F1.2: Members by LEZ public keys | ✅ | `[u8; 32]` AccountIds |
| F1.3: Config in state account | ✅ | `MultisigState` stored as PDA |
| F1.4: Treasury vault PDA | ✅ | `multisig_vault__` PDA derived |

### F2 — Transaction Execution

| Requirement | Status | Notes |
|-------------|--------|-------|
| F2.1: Any member can propose | ✅ | Membership check in propose.rs |
| F2.2: M distinct members must sign | ✅ | `has_threshold()` check in execute.rs |
| F2.3: Single on-chain transaction | ✅ | ChainedCall model |
| F2.4: Support native token transfers | ✅ | Via ChainedCall to token program |

### F3 — Member Management

| Requirement | Status | Notes |
|-------------|--------|-------|
| F3.1: Add member (M sigs required) | ❌ | Not implemented; listed in README Known Issues |
| F3.2: Remove member (M sigs required) | ❌ | Not implemented |
| F3.3: Change threshold (M sigs required) | ❌ | Not implemented |

**Note:** These are PoC scope. Listed as "Future Considerations" in SPEC.

### U1 — CLI Commands

| Command | Status | Notes |
|---------|--------|-------|
| `multisig create` | ⚠️ Exists but outdated | Needs update for member PDAs |
| `multisig info` | ⚠️ Exists but outdated | |
| `multisig propose` | ⚠️ Exists but outdated | Old 2-account layout |
| `multisig sign` | ⚠️ Exists but outdated | |
| `multisig execute` | ⚠️ Exists but outdated | |
| `multisig add-member` | ❌ Not implemented | Needs F3 first |
| `multisig remove-member` | ❌ Not implemented | Needs F3 first |

### R — Reliability

| Requirement | Status | Notes |
|-------------|--------|-------|
| R1: No funds without M valid sigs | ✅ | `has_threshold()` enforced before execute |
| R2: Nonce-based replay protection | ✅ | NSSA handles nonces |
| R3: Clear error messages | ✅ | `assert!` with descriptive messages throughout |

### P — Performance

| Requirement | Status | Notes |
|-------------|--------|-------|
| P1: Single on-chain tx for execute | ✅ | ChainedCall model |
| P2: O(M) signature verification | ✅ | One signer per approve tx |

### S — Supportability

| Requirement | Status | Notes |
|-------------|--------|-------|
| S1: Unit tests for all instructions | ⚠️ | `approve` and `reject` have unit tests; `create_multisig`, `propose`, `execute` do not |
| S2: Integration test (create→fund→propose→approve→execute) | ✅ | `e2e_tests/tests/e2e_multisig.rs` |

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

## README vs Implementation

The README is mostly accurate. One minor note:

- README `CreateMultisig` account layout shows `[state_pda, member1..N]` → ✅ correct
- README says "CLI needs update" in Known Issues → ✅ accurate and honest
- README e2e expected output → ✅ matches actual test output format

---

## Gaps to Address (Prioritized)

### High Priority
1. **Unit tests for create_multisig, propose, execute** (S1 FURPS gap)
   - `approve` and `reject` have good unit tests
   - Other handlers have no unit tests — relies entirely on e2e

### Medium Priority
2. **CLI update** for new 3-account instruction layout + proposal PDA flow
   - Currently broken by design (listed in Known Issues)
   - Blocks user-facing usability (U1 FURPS)

### Low Priority (Post-PoC)
3. **Member management**: AddMember, RemoveMember, ChangeThreshold (F3)
4. **CloseProposal**: Reclaim storage from executed/rejected proposals
5. **Time-lock**: Optional delay between threshold and execution
6. **FURPS update**: FURPS.md still references old offline-signing model (F2.3 says "single tx with all signatures" — now it's per-member approve txs). Should be updated to reflect Squads-style flow.
