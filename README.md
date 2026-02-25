# LEZ Multisig — M-of-N On-Chain Proposals

An M-of-N multisig governance program for the [Logos Execution Zone (LEZ)](https://github.com/logos-blockchain/lssa). Inspired by [Squads Protocol v4](https://squads.so/) — proposals live on-chain as separate PDA accounts. Signers approve asynchronously, no offline coordination needed.

📄 **[Technical Specification](SPEC.md)** — accounts, PDA derivation, instruction set, validation rules.

## How It Works

```
CreateMultisig → Propose → Approve (×M) → Execute → ChainedCall to target program
```

1. **Create** a multisig with N members, threshold M, and a unique `create_key`
2. **Propose** an action — creates a proposal PDA account, auto-approves the proposer
3. **Approve** — other members approve independently, each in their own transaction
4. **Execute** — once M approvals collected, emits a `ChainedCall` to the target program
5. **Reject** — members can reject; if rejections ≥ (N - M + 1), the proposal is dead

**Key design:** The multisig never executes actions directly. It collects votes and delegates execution via LEZ `ChainedCall`. For example, a token transfer goes: multisig approves → `ChainedCall` to token program → token program moves funds.

## Project Structure

```
lez-multisig/
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
│   └── guest/src/bin/multisig.rs
├── e2e_tests/               — integration tests against live sequencer
│   └── tests/e2e_multisig.rs
├── cli/                     — CLI (⚠️ needs update for new proposal PDA flow)
├── SPEC.md                  — full technical specification
└── docs/FURPS.md            — requirements specification
```

## Quick Start

### Prerequisites

- Rust nightly (edition 2024)
- [Risc0 toolchain](https://dev.risczero.com/api/zkvm/install): `curl -L https://risczero.com/install | bash && rzup install`
- Docker (for reproducible guest builds)
- Clone of [lssa](https://github.com/logos-blockchain/lssa) (for sequencer + token program binary)

### Important: Member Accounts

Members must use **fresh keypairs** (never-used accounts with nonce=0) for each multisig. During `CreateMultisig`, all member accounts are **claimed** by the multisig program (sets `program_owner = multisig_program_id`). This is required by LEZ validation rules — see [issue #339](https://github.com/logos-blockchain/lssa/issues/339).

### 1. Build the guest binary

```bash
cd lez-multisig

# Build the zkVM guest (produces the on-chain binary)
# This requires Docker and takes ~15-20 minutes on first run
cargo risczero build --manifest-path methods/guest/Cargo.toml

# Verify output exists
ls -la target/riscv32im-risc0-zkvm-elf/docker/multisig.bin
```

### 2. Run unit tests

```bash
# Core types + program handlers (4 tests)
cargo test -p multisig_core -p multisig_program
```

### 3. Run e2e tests

The e2e test deploys both the multisig and token programs to a local sequencer, then runs a full flow: create token → create multisig → fund vault → propose transfer → approve → execute via ChainedCall → verify balances.

```bash
# Terminal 1: Start the sequencer (from lssa repo)
cd /path/to/lssa
cargo run -p sequencer_runner --features standalone --release -- \
  sequencer_runner/configs/debug

# Terminal 2: Run the e2e test (from lez-multisig repo)
cd /path/to/lez-multisig

# Set required env vars
export MULTISIG_PROGRAM=$(pwd)/target/riscv32im-risc0-zkvm-elf/docker/multisig.bin
export TOKEN_PROGRAM=/path/to/lssa/artifacts/program_methods/token.bin
export SEQUENCER_URL=http://127.0.0.1:3040  # optional, this is the default

# Run
cargo test -p lez-multisig-e2e -- --nocapture
```

**Expected output:**
```
📦 Deploying programs...
  token deployed: <hash>
  multisig deployed: <hash>

═══ STEP 1: Create fungible token ═══
  Minter balance: Some(1000000)
  ✅ Token created, minter has 1,000,000 tokens

═══ STEP 2: Create 2-of-3 multisig ═══
  Multisig state PDA: <address>
  Vault PDA: <address>
  ✅ 2-of-3 multisig created!

═══ STEP 3: Transfer tokens to multisig vault ═══
  Vault balance: Some(500)
  ✅ Vault funded with 500 tokens!

═══ STEP 4: Propose transfer 200 tokens from vault ═══
  Proposal PDA: <address>
  ✅ Proposal #1 created (1/2 approvals)

═══ STEP 5: Member 2 approves ═══
  ✅ 2/2 approvals — ready to execute!

═══ STEP 6: Execute — transfer tokens via ChainedCall ═══

═══ STEP 7: Verify results ═══
  ✅ Proposal marked as executed
  Vault balance: Some(300)
  Recipient balance: Some(200)

🎉 Full multisig + token transfer e2e test PASSED!
```

## On-Chain State

See [SPEC.md](SPEC.md) for full details. Summary:

### Accounts

| Account | PDA Seed | Purpose |
|---------|----------|---------|
| Multisig State | `"multisig_state__" XOR create_key` | Config: members, threshold, tx counter |
| Proposal | `"multisig_prop___" XOR create_key XOR index` | Single proposal: action + votes |
| Vault | `"multisig_vault__" XOR create_key` | Holds assets controlled by multisig |

All PDAs: `AccountId = SHA256(LEZ_PREFIX ‖ program_id ‖ seed)`

### Instructions

| Instruction | Accounts | Description |
|---|---|---|
| `CreateMultisig` | `[state_pda, member1..N]` | Initialize multisig, claim member accounts |
| `Propose` | `[state_pda, proposer, proposal_pda]` | Create proposal, auto-approve proposer |
| `Approve` | `[state_pda, approver, proposal_pda]` | Add approval to proposal |
| `Reject` | `[state_pda, rejector, proposal_pda]` | Add rejection to proposal |
| `Execute` | `[state_pda, executor, proposal_pda, ...targets]` | Execute approved proposal via ChainedCall |

## Known Issues

- [ ] CLI needs update for proposal PDA flow ([current CLI uses old 2-account layout](cli/src/bin/multisig.rs))
- [ ] CLI requires `logos-blockchain-circuits` transitive dependency ([#1](https://github.com/jimmy-claw/lez-multisig/issues/1))
- [ ] No `CloseProposal` instruction yet (executed/rejected proposals stay on-chain)
- [ ] Config change instructions (`AddMember`, `RemoveMember`, `ChangeThreshold`) not yet implemented in program

## References

- [Technical Specification (SPEC.md)](SPEC.md)
- [FURPS Requirements](docs/FURPS.md)
- [LEZ Repository (LSSA)](https://github.com/logos-blockchain/lssa)
- [Squads Protocol v4](https://squads.so/) — design inspiration
