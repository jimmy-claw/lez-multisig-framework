# LEZ Multisig — M-of-N On-Chain Governance

An M-of-N multisig governance program for the [Logos Execution Zone (LEZ)](https://github.com/logos-blockchain/lssa). Inspired by [Squads Protocol v4](https://squads.so/) — proposals live on-chain as separate PDA accounts. Signers approve asynchronously, no offline coordination needed.

📄 **[Technical Specification](SPEC.md)** · 📋 **[Demo Runbook](scripts/DEMO-RUNBOOK.md)**

## How It Works

```
CreateMultisig → Propose → Approve (×M) → Execute → ChainedCall to target program
```

1. **Create** a multisig with N members, threshold M, and a unique `create_key`
2. **Propose** an action — stores a serialized instruction + target program ID in a proposal PDA, auto-approves the proposer
3. **Approve** — other members approve independently, each in their own transaction
4. **Execute** — once M approvals collected, emits a `ChainedCall` to the target program
5. **Reject** — members can reject; if rejections ≥ (N - M + 1), the proposal is dead

**Key design:** The multisig never executes actions directly. It delegates via LEZ `ChainedCall` — the proposal stores a serialized instruction (encoded from any program's IDL), which is delivered to the target program on execute. This makes multisig governance **composable with any LEZ program**.

## Project Structure

```
lez-multisig-framework/
├── multisig_core/           — shared types, instructions, PDA derivation
├── multisig_program/        — on-chain handlers (risc0 guest)
│   └── src/
│       ├── lib.rs           — instruction dispatch
│       ├── create_multisig.rs
│       ├── propose.rs
│       ├── approve.rs
│       ├── reject.rs
│       └── execute.rs
├── methods/                 — risc0 zkVM guest build config
├── cli/                     — thin CLI wrapper around lez-cli (IDL-driven)
├── idl-gen/                 — IDL generator (host-side, no risc0)
├── lez-multisig-ffi/        — FFI client + generated IDL
├── e2e_tests/               — integration tests against live sequencer
├── scripts/
│   ├── demo-full-flow.sh    — full end-to-end demo script
│   └── DEMO-RUNBOOK.md      — manual CLI runbook for live presentation
├── SPEC.md                  — full technical specification
├── FURPS.md                 — requirements specification
├── ADR.md                   — architecture decision records
└── docs/
```

## Quick Start

### Prerequisites

- Rust nightly (edition 2024)
- [Risc0 toolchain](https://dev.risczero.com/api/zkvm/install): `curl -L https://risczero.com/install | bash && rzup install`
- Docker (for reproducible guest builds)
- Clone of [lssa](https://github.com/logos-blockchain/lssa) (for sequencer + wallet + token binary)

### Important: Member Accounts

Members must use **fresh keypairs** (never-used accounts with nonce=0) for each multisig. During `CreateMultisig`, all member accounts are **claimed** by the multisig program (`program_owner = multisig_program_id`). This is required by LEZ validation rules.

### 1. Build the guest binary

```bash
# Build the zkVM guest — requires Docker, ~15-20 min on first run
cargo risczero build --manifest-path methods/guest/Cargo.toml

# Verify
ls target/riscv32im-risc0-zkvm-elf/docker/multisig.bin
```

### 2. Generate the IDL

```bash
# Regenerate from Rust source whenever instruction types change
cargo run -p idl-gen
# Output: lez-multisig-ffi/src/multisig_idl.json
```

### 3. Run unit tests

```bash
cargo test -p multisig_core -p multisig_program
```

### 4. Run the full demo

The demo script runs a complete flow against a local sequencer: deploy → register → create multisig → propose member additions → execute → token governance via ChainedCall.

```bash
# Terminal 1: start sequencer (from lssa repo)
RUST_LOG=info cargo run --features standalone -p sequencer_runner -- \
  sequencer_runner/configs/debug

# Terminal 2: run demo (set LSSA_DIR and REGISTRY_DIR first)
export LSSA_DIR=/path/to/lssa
export REGISTRY_DIR=/path/to/lez-registry
bash scripts/demo-full-flow.sh
```

See [scripts/DEMO-RUNBOOK.md](scripts/DEMO-RUNBOOK.md) for a manual step-by-step version.

### 5. Run e2e tests

```bash
# Requires running sequencer + token binary
export TOKEN_PROGRAM=/path/to/lssa/artifacts/program_methods/token.bin
cargo test -p lez-multisig-e2e -- --nocapture
```

## On-Chain State

See [SPEC.md](SPEC.md) for full details.

### Accounts

| Account | PDA Seed | Purpose |
|---------|----------|---------|
| Multisig State | `"multisig_state__" XOR create_key` | Config: members, threshold, tx counter |
| Proposal | `"multisig_prop___" XOR create_key XOR index` | Single proposal: action + votes |
| Vault | `"multisig_vault__" XOR create_key` | Holds assets controlled by multisig |

All PDAs: `AccountId = SHA256(program_id ‖ seed)`

**Derive any PDA from the CLI:**
```bash
multisig --idl multisig_idl.json --program-id <HEX> pda vault --create-key demo-abc
multisig --idl multisig_idl.json --program-id <HEX> pda multisig-state --create-key demo-abc
```

### Instructions

| Instruction | Accounts | Description |
|---|---|---|
| `CreateMultisig` | `[state_pda, member1..N]` | Initialize multisig, claim member accounts |
| `Propose` | `[state_pda, proposer, proposal_pda]` | Create proposal, auto-approve proposer |
| `Approve` | `[state_pda, approver, proposal_pda]` | Add approval to proposal |
| `Reject` | `[state_pda, rejector, proposal_pda]` | Add rejection to proposal |
| `Execute` | `[state_pda, executor, proposal_pda, ...targets]` | Execute approved proposal via ChainedCall |

## CLI

The `cli/` crate wraps [`lez-cli`](https://github.com/jimmy-claw/lez-framework), which auto-generates subcommands from the multisig IDL. All flags are derived from the IDL — no hardcoded commands.

```bash
# Build the CLI
cargo build -p multisig-cli

# View available commands (IDL-driven)
./target/debug/multisig --idl lez-multisig-ffi/src/multisig_idl.json --help

# Derive a PDA (no binary needed)
./target/debug/multisig --idl lez-multisig-ffi/src/multisig_idl.json \
  --program-id <64-char-hex> pda vault --create-key my-multisig

# Create a multisig (dry-run)
./target/debug/multisig --idl lez-multisig-ffi/src/multisig_idl.json \
  --program multisig.bin --dry-run \
  create-multisig \
    --create-key my-multisig \
    --threshold 2 \
    --members <member1_hex>,<member2_hex>,<member3_hex> \
    --member-accounts-account <m1_id> \
    --member-accounts-account <m2_id> \
    --member-accounts-account <m3_id>

# Propose a cross-program action (using target program's IDL)
# First serialize the target instruction (dry-run):
./target/debug/multisig --idl scripts/token-idl.json \
  --program token.bin --dry-run \
  transfer --amount-to-transfer 200
# Then propose using the serialized bytes:
./target/debug/multisig --idl lez-multisig-ffi/src/multisig_idl.json \
  --program multisig.bin \
  propose \
    --multisig-state-account <state_pda> \
    --proposer-account <signer_id> \
    --proposal-account <fresh_account> \
    --target-program-id <token_program_id_hex> \
    --target-instruction-data <u32_words_csv> \
    --target-account-count 2 \
    --pda-seeds <vault_seed_hex> \
    --authorized-indices 0
```

## Cross-Program Governance

The multisig can govern **any LEZ program** via ChainedCall. The proposal stores:
- `target_program_id` — which program to call
- `target_instruction_data` — serialized instruction bytes (from the target program's IDL)
- `target_account_count` — how many accounts the ChainedCall needs
- `pda_seeds` — seeds for PDA accounts the multisig owns (e.g. vault)

This means you can use lez-cli with any program's IDL to generate the instruction bytes, then wrap them in a multisig proposal — without writing any code.

## Basecamp UI Module

The `lez-multisig-module/` directory contains the Qt/QML Basecamp plugin. All files inside it are **fully generated** — do not edit them by hand.

### Code generation pipeline

```
multisig_program/src/lib.rs   (Rust annotations — edit this)
        │
        ▼  make generate-idl
lez-multisig-ffi/src/multisig_idl.json
        │
        ├─▶  make generate-ffi      → lez-multisig-ffi/src/multisig.rs
        ├─▶  make generate-header   → lez-multisig-ffi/include/lez_multisig.h
        └─▶  make generate-module   → lez-multisig-module/src/*.{h,cpp}
                                       lez-multisig-module/qml/Main.qml
```

Run all steps at once:

```bash
make generate        # IDL → FFI → C header → Qt module files
```

### First-time setup

```bash
# Install code generators (once)
cargo install --path /path/to/spel/spel-client-gen   # or: make install-tools (tagged release)
cargo install cbindgen --version 0.29.2

# Install Qt6 dev packages (Debian/Ubuntu)
apt install qt6-base-dev qt6-declarative-dev
```

### Build the plugin

```bash
make build-module    # compiles liblez_multisig_ffi.so + liblez_multisig_plugin.so + preview app
```

### Run the standalone preview app (no Basecamp needed)

```bash
make run-module      # launches lez_multisig_app with QML loaded from source
```

### Install into Basecamp

```bash
PLUGIN_DIR=~/.local/share/Logos/LogosBasecamp/plugins/lez_multisig
cp target/release/liblez_multisig_ffi.so   $PLUGIN_DIR/
cp lez-multisig-module/build/liblez_multisig_plugin.so $PLUGIN_DIR/
# then restart Basecamp
```

### Full regen + rebuild cycle

```bash
make generate build-module
```

### After changing `lib.rs` or the IDL generator (spel-client-gen)

If you update `spel-client-gen` locally, reinstall it before regenerating:

```bash
cargo install --path /path/to/spel/spel-client-gen
make generate build-module
```

## Known Issues

- [ ] No `CloseProposal` instruction yet (executed/rejected proposals stay on-chain)
- [ ] `ProposeConfig` (AddMember/RemoveMember/ChangeThreshold) not yet in program

## Dependencies

### v0.1

| Component | Role |
|---|---|
| [LSSA (LEZ runtime)](https://github.com/logos-blockchain/lssa) | ChainedCall, PDA derivation, account ownership, nonce replay protection |
| [Token Program](https://github.com/logos-blockchain/logos-execution-zone) | Native token (λ) transfers — primary ChainedCall target |
| [spel-framework](https://github.com/logos-co/spel) | IDL generation, FFI client codegen, C header |
| [RISC0 zkVM](https://github.com/risc0/risc0) | Guest program execution environment |

### v0.2

| Component | Role |
|---|---|
| [spel-client-gen](https://github.com/logos-co/spel) | Generates Basecamp Qt module (backend, plugin, QML scaffold) from IDL |
| [logos-lez-spelbook](https://github.com/vpavlin/spelbook) | On-chain LEZ program registry — program ID → IDL lookup for proposal decode/encode |
| Logos Messaging | In-band signing notifications; required for private TX flow |

## References

- [Technical Specification (SPEC.md)](SPEC.md)
- [FURPS Requirements (FURPS.md)](FURPS.md)
- [Architecture Decisions (ADR.md)](ADR.md)
- [Demo Runbook (scripts/DEMO-RUNBOOK.md)](scripts/DEMO-RUNBOOK.md)
- [LSSA (LEZ runtime)](https://github.com/logos-blockchain/lssa)
- [Squads Protocol v4](https://squads.so/) — design inspiration
