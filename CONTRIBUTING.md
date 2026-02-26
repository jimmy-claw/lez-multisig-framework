# Contributing to lez-multisig-framework

## Overview

This repo uses a **Rust annotations → IDL → FFI client** generation pipeline. Understanding this pipeline is essential before making changes.

## The Generation Pipeline

```
multisig_program/src/lib.rs   ← Edit THIS to change program interface
        │  (Rust macro annotations)
        ▼
lez-multisig-ffi/src/multisig_idl.json   ← GENERATED, do not edit
        │  (cargo run --bin generate_idl)
        ▼
lez-multisig-ffi/src/multisig.rs          ← GENERATED, do not edit
        │  (lez-client-gen)
        ▼
C FFI library (liblez_multisig_ffi.so)
```

## ⚠️ Never Edit Generated Files Directly

The following files are **generated** and **not tracked in git**:

- `lez-multisig-ffi/src/multisig_idl.json` — IDL generated from Rust macro annotations
- `lez-multisig-ffi/src/multisig.rs` — FFI client generated from the IDL

Both files have a `// GENERATED FILE` header. Do not edit them. Any manual edits will be overwritten the next time `make generate` is run.

## Making Changes to the Program Interface

1. **Edit `multisig_program/src/lib.rs`** — this is the single source of truth.
   - Account annotations: `#[account(init, pda = [literal("seed"), arg("param")])]`
   - Instruction arguments become IDL args and FFI JSON params automatically
   - See existing instructions as examples

2. **Regenerate everything:**
   ```bash
   make generate
   ```
   This runs two steps:
   - `make generate-idl` → writes `lez-multisig-ffi/src/multisig_idl.json`
   - `make generate-ffi` → writes `lez-multisig-ffi/src/multisig.rs`

3. **Verify it compiles:**
   ```bash
   cargo check
   ```

4. **Update callers** — if you changed instruction signatures, update:
   - `multisig_core/src/lib.rs` (the `Instruction` enum)
   - `e2e_tests/` (test code that constructs Instruction variants)
   - Any external consumers of the FFI

## PDA Seed Annotations

PDA derivation is expressed in the Rust source via `#[account(...)]` attributes:

```rust
// Single const seed
#[account(init, pda = literal("my_prefix"))]

// Arg seed (single)
#[account(init, pda = arg("create_key"))]

// Multi-seed: const + arg + arg (u64 supported via PR #41)
#[account(init, pda = [literal("multisig_prop___"), arg("create_key"), arg("proposal_index")])]
```

The macro generates the IDL's `pda.seeds` array, and `lez-client-gen` turns that into:
- A `compute_{account}_pda(...)` helper function in the generated FFI
- Automatic PDA resolution in the `{instruction}_impl` FFI functions

## Regeneration Commands Reference

| Command | What it does |
|---------|-------------|
| `make generate-idl` | Regenerate IDL from Rust annotations |
| `make generate-ffi` | Regenerate FFI client from IDL |
| `make generate` | Run both steps in order |
| `make check-generated` | Generate + check for unexpected drift (used in CI) |

## Commit Guidelines

- Generated files are in `.gitignore` and **must not be committed**
- Commit your `lib.rs` changes; CI regenerates and uploads the generated files as artifacts
- PR titles should mention the annotation change (not the generated output)
- Run `cargo check` before pushing — CI will also check

## Dependency on lez-framework

The `generate_idl` binary and `lez-client-gen` both come from the `lez-framework` git dependency:

- IDL generation: `lez_framework::generate_idl!` macro in `methods/guest/src/bin/generate_idl.rs`
- FFI generation: `lez-client-gen` crate from the same lez-framework repo

When lez-framework is updated (e.g. new PDA seed types), update the `branch = "main"` dep and re-run `make generate`.
