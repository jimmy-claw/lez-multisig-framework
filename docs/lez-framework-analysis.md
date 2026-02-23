# LEZ Framework Analysis for lez-multisig

**Date:** 2026-02-20  
**Author:** Jimmy (AI assistant)  
**Repo:** https://github.com/jimmy-claw/lez-framework  
**Subject:** Can lez-multisig be reimplemented using lez-framework?

---

## 1. What the Framework Provides

### 1.1 Core Macros (`lez-framework-macros`)

The framework's main proc-macro is `#[nssa_program]`, applied to a `mod` block containing `#[instruction]`-annotated functions. For each such module it generates:

| Generated artifact | Description |
|---|---|
| `Instruction` enum | Struct variants from fn signatures (args only, not accounts) |
| `PROGRAM_IDL_JSON: &str` | Compile-time JSON IDL const |
| `__program_idl() -> NssaIdl` | Runtime IDL object for tooling |
| `fn main()` | Full RISC Zero guest entry point: read → dispatch → write |
| Handler function bodies | Original fns with `#[instruction]` / `#[account]` attrs stripped |

#### Account constraints
Supported via `#[account(...)]` on `AccountWithMetadata` parameters:

| Attribute | Description | Generated effect |
|---|---|---|
| `mut` | Account is writable | IDL flag only |
| `init` | Account is being created | IDL flag, implies `mut` |
| `signer` | Must sign the transaction | IDL flag only (**no runtime check generated**) |
| `pda = literal("seed")` | PDA from constant string | IDL seed; **no runtime PDA verification** |
| `pda = account("name")` | PDA from another account's ID | IDL seed; not enforced |
| `owner = EXPR` | Expected program owner | IDL field; not enforced |

**Important:** The `generate_validation()` function in the macro currently returns an empty vec. No runtime constraint checks are generated — they are only reflected in the IDL.

### 1.2 Core Types (`lez-framework-core`)

| Type / Module | Purpose |
|---|---|
| `NssaResult` | `Result<NssaOutput, NssaError>` — return type for all instruction handlers |
| `NssaOutput` | Wraps `(Vec<AccountPostState>, Vec<ChainedCall>)` with `.states_only()`, `.with_chained_calls()` |
| `NssaError` | Structured error enum: `AccountCountMismatch`, `Unauthorized`, `InsufficientBalance`, `PdaMismatch`, `Custom`, etc. |
| `NssaIdl` / `IdlInstruction` / `IdlSeed` | IDL types for JSON generation and CLI |
| `AccountConstraint` | Metadata about account constraints (used by validation module) |
| `validate_accounts()` | Stub validation function (not yet connected to macro) |

### 1.3 CLI (`lez-framework-cli`)

A generic, IDL-driven CLI (`lez-cli`) providing:
- Auto-generated subcommands from IDL instructions
- Type-aware argument parsing (`u8`/`u64`/`u128`, `[u8; N]` as hex/UTF-8, `Vec<[u8; 32]>` as comma-separated, `program_id` as `u32,u32,...×8`)
- risc0 serialization (`serialize_to_risc0`)
- PDA computation from IDL seeds (single-seed only; multi-seed/arg-based returns `Err`)
- Transaction building + wallet integration
- `inspect` subcommand for extracting `ProgramId` from binaries
- `init` subcommand for project scaffolding

### 1.4 IDL Generation (`generate_idl!` macro)

A one-liner macro that reads a program source file at compile time, parses the `#[nssa_program]` module, and generates a `main()` printing the IDL as JSON.

---

## 2. Current lez-multisig Architecture

The multisig is a Squads Protocol v4-inspired M-of-N governance program with these instructions:

### Instructions

| Instruction | Accounts | Key args | Notes |
|---|---|---|---|
| `CreateMultisig` | `[multisig_state_pda, member_0, ..., member_N]` | `create_key: [u8;32]`, `threshold: u8`, `members: Vec<[u8;32]>` | Variable account count; PDA keyed by `create_key` |
| `Propose` | `[multisig_state, proposer, proposal_pda]` | `target_program_id`, `target_instruction_data`, `target_account_count`, `pda_seeds`, `authorized_indices` | Proposal stored as separate PDA; PDA keyed by `(create_key, proposal_index)` |
| `Approve` | `[multisig_state, approver, proposal_pda]` | `proposal_index: u64` | Fixed 3 accounts |
| `Reject` | `[multisig_state, rejector, proposal_pda]` | `proposal_index: u64` | Fixed 3 accounts |
| `Execute` | `[multisig_state, executor, proposal_pda, target_0, ..., target_K]` | `proposal_index: u64` | Variable trailing accounts |

### PDA derivation

Three PDA types, all using custom XOR-based mixing (not a standard hash):

```rust
// MultisigState PDA: xor("multisig_state__", create_key)
// Proposal PDA: xor("multisig_prop___", create_key) xor proposal_index.to_be_bytes() in last 8 bytes
// Vault PDA: xor("multisig_vault__", create_key)
```

### Program structure

- `multisig_core/` — shared types, `Instruction` enum, PDA helpers (`MultisigState`, `Proposal`, etc.)
- `multisig_program/` — instruction handlers, each in own file, `process()` dispatcher
- `methods/guest/` — thin `main()` glue
- `cli/` — custom `clap`-based CLI with full transaction submission
- `e2e_tests/` — full integration test with sequencer, token program, ChainedCalls

---

## 3. Mapping Analysis: Framework vs. Multisig

### 3.1 What Works Well ✅

#### NssaResult / NssaOutput / NssaError
The framework's return type pattern maps directly to the multisig handlers. Current handlers return `(Vec<AccountPostState>, Vec<ChainedCall>)` tuples; under the framework they would return `NssaResult` using `NssaOutput::states_only()` or `NssaOutput::with_chained_calls()`. This is a purely mechanical transformation.

#### `Approve`, `Reject` instructions (fixed accounts)
These have exactly 3 fixed `AccountWithMetadata` parameters and primitive args — a perfect fit for the current framework:

```rust
#[instruction]
pub fn approve(
    #[account(mut)]
    multisig_state: AccountWithMetadata,
    #[account(signer)]
    approver: AccountWithMetadata,
    #[account(mut)]
    proposal: AccountWithMetadata,
    proposal_index: u64,
) -> NssaResult {
    // Business logic unchanged
}
```

The macro would generate correct account destructuring and dispatch.

#### `Propose` instruction (fixed accounts)
Also 3 fixed accounts — the complex args (`InstructionData`, `Vec<[u8;32]>`) would be in the enum variant. This maps cleanly.

#### IDL generation
The framework can auto-generate IDL for the simple instructions. The existing custom CLI could potentially be replaced by `lez-cli` once PDA computation supports dynamic seeds.

#### `ChainedCall` support
`NssaOutput::with_chained_calls()` directly supports ChainedCalls, which is central to the multisig's `Execute` instruction.

---

### 3.2 What's Missing / Blocked ❌

#### BLOCKER 1: Dynamic/arg-based PDA seeds
**GitHub Issue:** https://github.com/jimmy-claw/lez-framework/issues/2

The multisig's PDAs are derived from instruction args (`create_key`, `proposal_index`), not from constants or other accounts. The framework currently only supports:
- `literal("string")` — constant
- `account("name")` — another account's ID

There is no `arg("name")` support in the macro's code generation (it's in the IDL type but not implemented). Without this, the framework cannot:
1. Auto-compute PDAs for `multisig_state` and `proposal` accounts
2. Verify PDA correctness in generated dispatch code

**Workaround:** Manual PDA computation before calling the handler (existing behavior) — but then the framework's PDA abstraction is bypassed entirely.

Additionally, the multisig uses a custom XOR-based seed mixing scheme. If the framework standardizes on SHA-256 for multi-part seeds, there would be a format incompatibility with any previously deployed multisig. A migration or a configurable combiner would be needed.

#### BLOCKER 2: Variable-count account lists
**GitHub Issue:** https://github.com/jimmy-claw/lez-framework/issues/3

Two instructions require runtime-variable account counts:

- **`CreateMultisig`**: `accounts = [multisig_state] + N member accounts`, where N = `members.len()` (instruction arg)
- **`Execute`**: `accounts = [multisig_state, executor, proposal] + K target accounts`, where K = `proposal.target_account_count` (from on-chain state)

The framework's macro generates:
```rust
let [acc1, acc2, ...] = <[_; N]>::try_from(pre_states).unwrap();
```
This is a compile-time fixed count. There is no mechanism to express "N fixed accounts plus a variable-length tail" in the current `#[account(...)]` attribute system.

**Workaround:** Write a `main()` manually for these instructions, mixing framework-style handlers with manual dispatch — which is essentially what lez-multisig already does.

#### Issue 3: No runtime signer validation generated
**GitHub Issue:** https://github.com/jimmy-claw/lez-framework/issues/4

The `#[account(signer)]` constraint is recorded in the IDL but `generate_validation()` returns an empty vec — no runtime checks are injected. The multisig handlers manually check `account.is_authorized`. This is a correctness gap: a future program that relies on the framework for authorization safety would have a security hole.

**Impact:** Not a blocker for migration (manual checks still work) but reduces the value proposition of the framework.

#### Issue 4: Conflict with existing `Instruction` enum in `multisig_core`
**GitHub Issue:** https://github.com/jimmy-claw/lez-framework/issues/5

The framework always generates its own `Instruction` enum from `#[instruction]` function signatures. The multisig already has a hand-crafted `Instruction` type in `multisig_core` that is shared with the CLI and test suite.

If `#[nssa_program]` is used, there will be a naming conflict unless the existing enum is removed and all host-side code updated to use the macro-generated one. This is a significant refactor — the `multisig_core` enum has careful variants with complex types (`InstructionData`, `ProgramId`, `Vec<[u8;32]>`) that the framework's IDL type system doesn't fully cover.

**Workaround:** Rename or namespace one of the enums, but this breaks the shared-type pattern. Or use `extern_instruction` if/when implemented (issue #5).

---

### 3.3 Summary Matrix

| Component | Framework support | Notes |
|---|---|---|
| `Instruction` enum generation | ⚠️ Partial | Conflicts with existing `multisig_core::Instruction` |
| `fn main()` dispatch | ✅ Yes | For fixed-account instructions |
| Fixed-account instructions (`Approve`, `Reject`) | ✅ Full | Direct 1:1 mapping |
| Fixed-account instruction (`Propose`) | ✅ Full | Complex args, but framework handles them |
| Variable-account instruction (`CreateMultisig`) | ❌ Blocked | Issue #3 |
| Variable-account instruction (`Execute`) | ❌ Blocked | Issue #3 |
| Static PDA derivation | ✅ Yes | `literal("seed")` works |
| Dynamic PDA from arg (`create_key`) | ❌ Blocked | Issue #2 |
| Dynamic PDA from arg (`proposal_index`) | ❌ Blocked | Issue #2 |
| Custom XOR seed mixing | ❌ Not supported | Framework will standardize on hash-based |
| Signer enforcement | ⚠️ IDL only | Issue #4 (no runtime check generated) |
| ChainedCall output | ✅ Yes | `NssaOutput::with_chained_calls()` |
| Structured errors (`NssaError`) | ✅ Yes | Replace `assert!` / `panic!` |
| IDL generation | ✅ Yes | For supported instructions |
| Generic CLI | ⚠️ Partial | Single-seed PDAs only; arg-based blocked |

---

## 4. Conclusion: Is Migration Possible?

### **Partial migration is possible today. Full migration is blocked by 2 issues.**

**What can be migrated now:**
- `Approve`, `Reject`, `Propose` instructions → direct `#[instruction]` functions
- Return types → `NssaResult` / `NssaOutput`
- Error handling → `NssaError` variants
- IDL generation for those 3 instructions

**What requires framework enhancements first:**
- `CreateMultisig` → needs **issue #3** (variable accounts)
- `Execute` → needs **issue #3** (variable accounts)
- PDA auto-computation/verification → needs **issue #2** (arg-based seeds)
- Signer auto-enforcement → needs **issue #4** (validation codegen)

**What requires a design decision:**
- The custom XOR-based seed mixing → either standardize to match framework conventions, or add a configurable seed combiner in the framework
- The `multisig_core::Instruction` shared type → either replace with macro-generated enum (breaking shared type pattern) or implement **issue #5**

### Recommendation

Do **not** attempt a full migration yet. The two blocker issues (#2 and #3) are architectural — they require significant macro and CLI changes. A partial migration that uses the framework for the simple instructions (`Approve`, `Reject`, `Propose`) while keeping manual dispatch for `CreateMultisig` and `Execute` would be messy and not worth the churn.

**Better path:**
1. Implement framework issues #2 and #3 first
2. Then migrate in one pass

The framework is well-designed and clearly headed in the right direction. Once blockers are resolved, lez-multisig would be a good reference implementation / showcase for the framework.

---

## 5. Issues Created

| # | Title | Label |
|---|---|---|
| [#2](https://github.com/jimmy-claw/lez-framework/issues/2) | Support dynamic/arg-based PDA seeds | blocker, enhancement |
| [#3](https://github.com/jimmy-claw/lez-framework/issues/3) | Variable-count accounts: support dynamic account lists | blocker, enhancement |
| [#4](https://github.com/jimmy-claw/lez-framework/issues/4) | Expose `is_authorized` (signer) flag in generated dispatch | good first issue |
| [#5](https://github.com/jimmy-claw/lez-framework/issues/5) | Custom Instruction enum: allow programs to use their own hand-crafted Instruction type | enhancement |

---

## Appendix: Framework Crate Dependency Map

```
lez-framework (umbrella)
├── lez-framework-macros   (proc macros: #[nssa_program], generate_idl!)
└── lez-framework-core     (IDL types, NssaError, NssaOutput, validation)
    └── nssa_core           (from logos-blockchain/lssa)

lez-framework-cli          (generic IDL-driven CLI)
├── lez-framework-core
├── nssa_core
├── nssa                    (from lssa)
└── wallet                  (from lssa)
```

## Appendix: lez-multisig Dependency Map

```
lez-multisig (workspace)
├── multisig_core           (Instruction enum, MultisigState, Proposal, PDA helpers)
├── multisig_program        (handler fns: create_multisig, propose, approve, reject, execute)
├── methods/guest           (RISC Zero guest: main() → multisig_program::process())
├── cli                     (clap CLI with manual transaction building)
└── e2e_tests               (full integration test against live sequencer)
```
