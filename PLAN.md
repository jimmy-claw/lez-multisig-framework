# Multisig UI Plan

## 1. Screen Wireframes

### Screen 1 — Dashboard (list of multisigs you belong to)

```
┌─────────────────────────────────────────────────────┐
│  Multisig Wallets                    [+ New Multisig]│
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  Treasury                          2-of-3   │    │
│  │  0xabc...def                                │    │
│  │  ● 2 pending proposals                      │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  Grants Committee                  3-of-5   │    │
│  │  0x123...789                                │    │
│  │  ● 1 pending proposal                       │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  Dev Fund                          1-of-2   │    │
│  │  0xfff...000                                │    │
│  │  ✓ No pending proposals                     │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Screen 2 — Multisig Detail (proposals list)

```
┌─────────────────────────────────────────────────────┐
│  ← Treasury                              2-of-3     │
│  0xabc...def  Members: Alice, Bob, Carol            │
├─────────────────────────────────────────────────────┤
│  Proposals                       [+ New Proposal]   │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  #4  Transfer 1000 LEZ to 0xgrant...        │    │
│  │  token · transfer_tokens                    │    │
│  │  ████████░░  2/3 approved     [Approve] [X] │    │
│  │  Proposed by Alice · 2h ago                 │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  #3  Mint 500 LEZ to 0xdev...               │    │
│  │  token · mint_tokens                        │    │
│  │  ████████████  3/3 approved        [Execute]│    │
│  │  Proposed by Bob · 1d ago                   │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  #2  Unknown instruction (0xdeadbeef...)    │    │
│  │  program: 0xcafe...  ⚠ IDL not in spelbook │    │
│  │  ████░░░░░░░░  1/3 approved   [Approve] [X] │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Screen 3 — Proposal Detail

```
┌─────────────────────────────────────────────────────┐
│  ← Treasury > Proposals                             │
│  Proposal #4                            [PENDING]   │
├─────────────────────────────────────────────────────┤
│  Action                                             │
│  ┌─────────────────────────────────────────────┐   │
│  │  Program:  Token (v1.2.0) · 0xtoken...      │   │
│  │  Function: transfer_tokens                  │   │
│  │                                             │   │
│  │  Arguments                                  │   │
│  │  ─────────────────────────────────────      │   │
│  │  recipient   0xgrant...abc                  │   │
│  │  amount      1000                           │   │
│  │  memo        "Q2 grant disbursement"        │   │
│  │                                             │   │
│  │  Accounts                                   │   │
│  │  ─────────────────────────────────────      │   │
│  │  [0] 0xsender...  (signer)                 │   │
│  │  [1] 0xrecip...                             │   │
│  └─────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────┤
│  Approvals  2 / 3                                   │
│  ┌─────────────────────────────────────────────┐   │
│  │  ✓ Alice   approved 2h ago                  │   │
│  │  ✓ Bob     approved 1h ago                  │   │
│  │  ○ Carol   pending                          │   │
│  └─────────────────────────────────────────────┘   │
│                                    [Approve] [Reject]│
└─────────────────────────────────────────────────────┘
```

### Screen 4 — New Proposal: Step 1 — Find Program

```
┌─────────────────────────────────────────────────────┐
│  New Proposal  1 ── 2 ── 3                          │
│  Step 1: Choose target program                      │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Search spelbook registry                           │
│  ┌─────────────────────────────────────────────┐   │
│  │  🔍 token                                   │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  Results                                            │
│  ┌─────────────────────────────────────────────┐   │
│  │  Token Program  v1.2.0                      │   │
│  │  0xtoken...abc  · by logos-co               │   │
│  │  LEZ fungible token transfers and minting   │   │
│  │                                  [Select →] │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  ─── or paste program ID directly ──────────────   │
│  ┌─────────────────────────────────────────────┐   │
│  │  0x...                                      │   │
│  └─────────────────────────────────────────────┘   │
│  ⚠ Program not in spelbook — args cannot be decoded │
│                                   [Continue anyway] │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Screen 5 — New Proposal: Step 2 — Pick Instruction

```
┌─────────────────────────────────────────────────────┐
│  New Proposal  1 ── 2 ── 3                          │
│  Step 2: Choose instruction  (Token Program v1.2.0) │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │  ● transfer_tokens                          │   │
│  │    Move tokens between accounts             │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │  ○ mint_tokens                              │   │
│  │    Create new tokens                        │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │  ○ burn_tokens                              │   │
│  │    Destroy tokens from an account           │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│                            [← Back]  [Next →]       │
└─────────────────────────────────────────────────────┘
```

### Screen 6 — New Proposal: Step 3 — Fill Arguments

```
┌─────────────────────────────────────────────────────┐
│  New Proposal  1 ── 2 ── 3                          │
│  Step 3: Fill arguments  (transfer_tokens)          │
├─────────────────────────────────────────────────────┤
│                                                      │
│  recipient  AccountId                               │
│  ┌─────────────────────────────────────────────┐   │
│  │  0x...                                      │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  amount  u64                                        │
│  ┌─────────────────────────────────────────────┐   │
│  │  1000                                       │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  memo  String  (optional)                           │
│  ┌─────────────────────────────────────────────┐   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  Encoded instruction preview                        │
│  ┌─────────────────────────────────────────────┐   │
│  │  0x0100000...  (32 bytes)          [Copy]   │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│                      [← Back]  [Submit Proposal]    │
└─────────────────────────────────────────────────────┘
```

---

## 2. Spelbook Integration Analysis

### What spelbook provides to multisig

| Need | Spelbook API | Where used |
|---|---|---|
| Find target program by name | `listPrograms()` / `getProgram(id)` | Proposal wizard Step 1 search |
| Resolve program ID → IDL | `getProgram(id)` → `idl_cid` → `fetchIdl(cid)` | Proposal detail decode, Step 2 instruction list |
| Human-readable program name | `ProgramEntry.name, version` | All cards / headers |

### What spel-framework provides

| Need | Approach |
|---|---|
| Encode args → `instruction_data` bytes | spel-framework codec with IDL JSON |
| Decode `instruction_data` bytes → args | spel-framework codec with IDL JSON |

### Proposal creation flow (Steps 1→3)

1. Multisig calls spelbook module: `logos.callModule("spelbook", "searchPrograms", {query})` → `[{program_id, name, version, idl_cid}]`
2. Multisig calls spelbook module: `logos.callModule("spelbook", "fetchIdl", {idl_cid})` → IDL JSON string
3. Multisig renders instruction picker from IDL, user fills form
4. Multisig calls spel-framework (FFI): `spel_encode(idl_json, instruction_name, args_json)` → `instruction_data` bytes
5. Multisig calls `propose_transaction(multisig_id, target_program_id, instruction_data, accounts)`

### Proposal decode flow (Proposal Detail screen)

1. Multisig has `target_program` (program_id bytes) and `instruction_data` from on-chain proposal
2. Multisig calls spelbook: `getProgram(target_program_id_hex)` → `idl_cid`
3. Multisig calls spelbook: `fetchIdl(idl_cid)` → IDL JSON
4. Multisig calls spel-framework: `spel_decode(idl_json, instruction_data)` → `{name, args}` JSON
5. Renders decoded args table — or shows "⚠ not in spelbook" fallback

### Gaps in spelbook today

1. **`fetchIdl` not exposed as Q_INVOKABLE** — only `listPrograms` / `getProgram` / `registerProgram` exist. Need to add `fetchIdl(cid: String) → String` (IDL JSON).
2. **Hex program_id lookup** — spelbook stores `program_id` as `[u32;8]` internally; the module must accept the same hex format multisig has on-chain. Need to verify the conversion is consistent.
3. **spel-framework codec FFI** — no Rust FFI wrapper yet for encode/decode from IDL. Biggest new piece: `spel_encode(idl_json, ix_name, args_json) → Vec<u8>` and `spel_decode(idl_json, bytes) → String`. These would live in `lez-multisig-ffi` or a shared crate.

### Inter-module communication pattern

The multisig Qt module calls spelbook via `logos.callModule()` signal/slot mechanism. This keeps the FFI boundary clean — multisig doesn't link against spelbook's `.so` directly. Both sides communicate via JSON strings.

---

## 3. Implementation Plan

### Phase 0 — Spelbook enhancements ✅ DONE

- [x] Add `fetchIdl(idl_cid: String)` Q_INVOKABLE to spelbook Qt module — calls `lez_storage_fetch_idl(cid)` FFI, returns IDL JSON string
- [x] Add `searchPrograms(query: String)` Q_INVOKABLE — local JSON cache search via `lez_registry_search` FFI; cache at `~/.local/share/spelbook/programs.json`
- [x] `getProgram` + `register` auto-populate cache so search works offline after any registry query
- [x] Verify program_id hex ↔ `[u32;8]` conversion is consistent between multisig and spelbook — both now use `u32::from_le_bytes` (spel-client-gen canonical convention)
- [x] `LezSpelbookBridge.h` added to lez-multisig module; wired as `spelbook` context property
- [x] Spelbook search integrated in propose dialog (encode-from-IDL mode)
- [x] Spelbook IDL fallback in proposal decode (`tryDecode`)

**Deliver:** spelbook module with `fetchIdl` + `searchPrograms` (vpavlin/spelbook `feat/spelbook-qt-module`); multisig wired to spelbook FFI ✅

### Phase 1 — spel-framework codec FFI ✅ DONE

- [x] Add `lez_multisig_encode_instruction(idl_json, ix_name, args_json) → CString` to `lez-multisig-ffi/src/codec.rs`
- [x] Add `lez_multisig_decode_instruction(idl_json, words_json) → CString` returning `{instruction, args}` JSON
- [x] Expose both in `lez_multisig.h` via cbindgen (`make generate-header`)
- [x] Expose both as Q_INVOKABLE via `LezMultisigCodec.h` (tracked) registered as `codec` context property

**Deliver:** QML calls `codec.encodeInstruction(idl, name, args)` and `codec.decodeInstruction(idl, wordsJson)`

### Phase 2 — Dashboard + Multisig Detail (read-only) ✅ DONE

- [x] Dashboard: watch/create dialogs; card list from persisted createKeys in fieldHistory
- [x] Multisig detail: sequential proposal fetch (state machine via `_fetchNext`/`_fetchTarget`)
- [x] Proposal card: target program hex shown; config_action decoded inline
- [x] Approval bar: colored progress at `approvals / threshold`; green when executable

**Deliver:** read-only browsing of all multisigs and proposals ✅

### Phase 3 — Proposal Detail decode ✅ DONE (fallback path; spelbook path blocked on Phase 0)

- [x] Per-proposal Decode button: tries codec with multisig IDL, shows decoded args inline
- [x] Error shown inline if decode fails (e.g. wrong IDL for the target program)
- [x] Approve / Execute / Reject buttons via account picker dialog
- [x] Full path: spelbook IDL lookup by target_program_id → decode (spelbook cache search + Codex fetch)

**Deliver:** fallback decode (multisig IDL) + spelbook-backed decode + action buttons ✅

### Phase 4 — New Proposal wizard ✅ DONE (Encode-from-IDL mode; spelbook search pending Phase 0)

- [x] Raw words mode: paste u32 words directly (advanced)
- [x] Encode-from-IDL mode: paste IDL JSON + instruction name + args JSON → live encode via codec → words pre-filled
- [x] Spelbook search (Step 1): search field in encode-from-IDL mode → select program → auto-populate target + IDL
- [ ] Instruction picker from IDL (Step 2): show instruction list from IDL instead of manual name entry (future improvement)

**Deliver:** spelbook-integrated encode-from-IDL propose flow ✅

### Phase 5 — Create Multisig + governance ✅ DONE

- [x] Create Multisig dialog: threshold + member list
- [x] Watch (add existing by createKey) dialog
- [x] Propose Add Member dialog
- [x] Propose Remove Member dialog
- [x] Propose Change Threshold dialog

**Deliver:** complete onboarding + governance flow ✅

---

## 4. Verification Plan

| Phase | What to verify | How |
|---|---|---|
| 0 | `fetchIdl` returns valid IDL JSON | spelbook unit test + manual call via `logoscore --call` |
| 1 | `spel_encode` round-trips through `spel_decode` | Rust unit tests with known IDL fixtures |
| 1 | C header exports both codec functions | `nm -D liblez_multisig_ffi.so \| grep spel_encode` |
| 2 | Dashboard loads multisigs from sequencer | Run against local sequencer with known state |
| 2 | Approval bar renders correct fraction | Screenshot at 0/3, 1/3, 2/3, 3/3 |
| 3 | Decoded args match what was submitted | Create known proposal, verify decode matches original args |
| 3 | Approve action changes on-chain state | Query proposal after approve, confirm approval count +1 |
| 4 | Wizard produces valid `instruction_data` | Submit proposal from wizard, verify decode in detail screen matches |
| 4 | Unknown program ID shows fallback UI | Use a program ID not registered in spelbook |
| 5 | Created multisig appears on dashboard | Create → navigate back → card visible with correct threshold |
