# Architecture Decision Records — LEZ Multisig

## ADR-1: On-chain proposal model (Squads-style)

**Decision:** Use on-chain proposals — each proposed action is stored as a separate PDA account. Members approve asynchronously in their own independent transactions.

**Alternatives considered:** Offline signature aggregation (collect N signatures off-chain, broadcast once).

**Rationale:** Offline aggregation requires coordination, a rendezvous channel, and a designated broadcaster. On-chain proposals are self-describing (any member can query status at any time), need no coordination infrastructure, and integrate naturally with the LEZ account model. The tradeoff is higher storage cost per proposal, accepted for PoC scope.

---

## ADR-2: Delegation via ChainedCall

**Decision:** The multisig never modifies external state directly. On execute it emits a `ChainedCall` to the target program (e.g., token program), which carries the serialized instruction.

**Rationale:** Keeps multisig surface area minimal — it only handles governance logic (threshold checks, approval tracking). Any LEZ program becomes a valid target without changes. The multisig is a composable governance wrapper, not an executor.

---

## ADR-3: PDA-based account model

**Decision:** Multisig State, Proposal, and Vault are all Program Derived Accounts (PDAs). Addressing is deterministic from (`program_id`, `create_key`) for the multisig and (`multisig_id`, `proposal_index`) for proposals.

**Rationale:** Deterministic addressing means no account registry is needed. The vault PDA is owned by the multisig program, ensuring funds can only move through the approved proposal flow.

---

## ADR-4: Member account claiming

**Decision:** Member accounts must be fresh keypairs dedicated to each multisig. During `CreateMultisig`, all member accounts are claimed by the multisig program.

**Rationale:** LEZ runtime requires explicit account claiming before a program can write to an account. Reusing existing keypairs would conflict with their existing owners. This is a runtime constraint, not a design preference — see [LSSA #339](https://github.com/logos-blockchain/lssa/issues/339).

**Known limitation:** Users must generate and manage a dedicated keypair per multisig membership. Future runtime changes (LSSA #339) may relax this.

---

## ADR-5: CLI-first interface for v0.1

**Decision:** v0.1 ships a standalone CLI; no GUI.

**Rationale:** Validates the on-chain program logic end-to-end with minimal investment. GUI (Basecamp Qt module via `spel-client-gen`) is scoped to v0.2 after the core program is stable.

---

## ADR-6: Signer management included in v0.1

**Decision:** `AddMember`, `RemoveMember`, and `ChangeThreshold` are implemented as `ProposeConfig` variants — they go through the same propose → approve → execute flow as any other multisig action, gated by the current threshold.

**Rationale:** Member management reuses the existing proposal machinery rather than adding a separate code path. A threshold guard on `RemoveMember` ensures N never drops below M.
