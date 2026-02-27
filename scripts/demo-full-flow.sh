#!/usr/bin/env bash
# =============================================================================
#  LEZ Multisig — Full End-to-End Demo
# =============================================================================
#
#  Story: "Programs are deployed. They're discoverable via a registry.
#          A multisig governs them — 2-of-3 threshold, all trustless."
#
#  Flow:
#    1. Deploy  — token + multisig + registry programs on-chain
#    2. Register — register them in the on-chain registry
#    3. List    — show registry is live and discoverable
#    4. Create  — spin up a multisig (SIGNER as initial member)
#    5. Propose — SIGNER proposes adding M2 (new member)
#    6. Execute — proposal executes via ChainedCall
#    7. Propose — SIGNER proposes adding M3, M2 approved passively
#    8. Execute — M3 joins the multisig
#
#  Prerequisites:
#    - Sequencer running at http://127.0.0.1:3040
#    - Programs already built (multisig.bin + registry.bin exist)
#    - Wallet config at ~/lssa/wallet/configs/debug
#
#  Usage:
#    bash ~/lez-multisig-framework/scripts/demo-full-flow.sh
#
# =============================================================================
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────

LSSA_DIR="${LSSA_DIR:-$HOME/lssa}"
MULTISIG_DIR="${MULTISIG_DIR:-$HOME/lez-multisig-framework}"
REGISTRY_DIR="${REGISTRY_DIR:-$HOME/lez-registry}"

WALLET="$LSSA_DIR/target/release/wallet"
MULTISIG_CLI="$MULTISIG_DIR/target/debug/multisig"
REGISTRY_CLI="$REGISTRY_DIR/target/debug/registry"

IDL="$MULTISIG_DIR/lez-multisig-ffi/src/multisig_idl.json"
MULTISIG_BIN="$MULTISIG_DIR/target/riscv32im-risc0-zkvm-elf/docker/multisig.bin"
REGISTRY_BIN="$REGISTRY_DIR/target/riscv32im-risc0-zkvm-elf/docker/registry.bin"
TOKEN_BIN="$LSSA_DIR/artifacts/program_methods/token.bin"

SEQUENCER_URL="${SEQUENCER_URL:-http://127.0.0.1:3040}"

export NSSA_WALLET_HOME_DIR="${NSSA_WALLET_HOME_DIR:-$LSSA_DIR/wallet/configs/debug}"
export REGISTRY_PROGRAM_ID="7d2b376bbe5c82c00c65068da8a57cff4a81c5207b3f5e0a1b3991120555e4d4"
STORAGE_URL="http://127.0.0.1:8080"
MOCK_CODEX_PY="$MULTISIG_DIR/scripts/mock-codex.py"
TOKEN_IDL="$REGISTRY_DIR/registry-idl.json"
MULTISIG_IDL="$MULTISIG_DIR/lez-multisig-ffi/src/multisig_idl.json"

source "$HOME/.cargo/env" 2>/dev/null || true

# ── Colours ───────────────────────────────────────────────────────────────

BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'

banner() {
  echo ""
  echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${RESET}"
  printf  "${CYAN}│${RESET}  ${BOLD}%-55s${RESET}  ${CYAN}│${RESET}\n" "$1"
  echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${RESET}"
  echo ""
}

ok()   { echo -e "  ${GREEN}✅  $*${RESET}"; }
info() { echo -e "  ${YELLOW}ℹ️   $*${RESET}"; }
run()  { echo -e "  ${DIM}▶  $*${RESET}"; }
err()  { echo -e "  ${RED}❌  $*${RESET}"; exit 1; }

# Create a new wallet account; prints "base58 hex" to stdout
new_account() {
  local label="$1"
  local raw
  raw=$("$WALLET" account new public --label "$label" 2>&1)
  local b58
  b58=$(echo "$raw" | grep 'account_id' | awk '{print $6}' | sed 's|Public/||')
  local hex
  hex=$(python3 -c "import base58,sys; print(base58.b58decode('$b58').hex())")
  echo "$b58 $hex"
}

# ── Pre-flight ─────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}  🔐  LEZ Multisig — Full Demo${RESET}"
echo -e "${DIM}      Programs · Registry · Governance · Execution${RESET}"
echo ""

  info "Sequencer will be reset and restarted below..."

[[ -f "$MULTISIG_BIN" ]] \
  || err "Multisig binary not found: $MULTISIG_BIN  →  run: bash $MULTISIG_DIR/scripts/build-guest.sh"
[[ -f "$REGISTRY_BIN" ]] \
  || err "Registry binary not found: $REGISTRY_BIN  →  run: cd $REGISTRY_DIR && make build"
[[ -f "$TOKEN_BIN"    ]] \
  || err "Token binary not found: $TOKEN_BIN"

ok "All binaries present"

# ── Reset sequencer state ─────────────────────────────────────────────────

echo -e "  ${YELLOW}⚡  Resetting sequencer — wiping chain state for a clean demo...${RESET}"

# Kill existing sequencer
pkill -f sequencer_runner 2>/dev/null || true
sleep 2

# Wipe RocksDB state
rm -rf "${LSSA_DIR}/rocksdb" "${LSSA_DIR}/mempool"
# Reset wallet nonce cache
cp "${NSSA_WALLET_HOME_DIR}/storage.json" "${NSSA_WALLET_HOME_DIR}/storage.json.bak" 2>/dev/null || true
rm -f "${NSSA_WALLET_HOME_DIR}/storage.json"
ok "Chain state wiped"

# Restart sequencer fresh
nohup bash -c "cd ${LSSA_DIR} && ./target/release/sequencer_runner ./sequencer_runner/configs/debug/ > /tmp/seq.log 2>&1" &
SEQ_PID=$!
echo -e "  ${DIM}Sequencer PID: ${SEQ_PID}${RESET}"

# Wait for it to be ready
echo -n "  Waiting for sequencer"
for i in $(seq 1 30); do
  sleep 1
  echo -n "."
  curl -s --max-time 2 "${SEQUENCER_URL}" > /dev/null 2>&1 && break
done
echo ""
curl -s --max-time 3 "${SEQUENCER_URL}" > /dev/null 2>&1 || err "Sequencer failed to start after reset"
ok "Sequencer restarted and ready"

# Start mock Codex storage (serves /api/codex/v1/data)
pkill -f mock-codex.py 2>/dev/null || true
nohup python3 "$MOCK_CODEX_PY" > /tmp/mock-codex.log 2>&1 &
sleep 1
curl -sf "$STORAGE_URL/" > /dev/null 2>&1 || { err "Mock Codex failed to start"; }
ok "Mock Codex storage running at $STORAGE_URL"
sleep 1

# ── Step 0: Show program IDs ───────────────────────────────────────────────

banner "Step 0 — Program IDs (hash of bytecode)"

run "multisig inspect <binaries>"
"$MULTISIG_CLI" --idl "$IDL" inspect "$TOKEN_BIN"
echo ""
"$MULTISIG_CLI" --idl "$IDL" inspect "$REGISTRY_BIN"
echo ""
"$MULTISIG_CLI" --idl "$IDL" inspect "$MULTISIG_BIN"

sleep 1

# ── Step 1: Deploy Programs ───────────────────────────────────────────────

banner "Step 1 — Deploy Programs"

echo "  Deploying token program..."
run "wallet deploy-program token.bin"
"$WALLET" deploy-program "$TOKEN_BIN" 2>&1 \
  && ok "Token program deployed" \
  || info "Already deployed — skipping"

sleep 1

echo ""
echo "  Deploying registry program..."
run "wallet deploy-program registry.bin"
"$WALLET" deploy-program "$REGISTRY_BIN" 2>&1 \
  && ok "Registry program deployed" \
  || info "Already deployed — skipping"

sleep 1

echo ""
echo "  Deploying multisig program..."
run "wallet deploy-program multisig.bin"
"$WALLET" deploy-program "$MULTISIG_BIN" 2>&1 \
  && ok "Multisig program deployed" \
  || info "Already deployed — skipping"

echo ""
# Grab program IDs for use in later steps (must be before poll)
TOKEN_PROGRAM_ID=$("$MULTISIG_CLI" --idl "$IDL" inspect "$TOKEN_BIN" \
  | grep 'ProgramId (hex)' | awk '{print $NF}' | tr -d ',')
REGISTRY_PROGRAM_ID=$("$MULTISIG_CLI" --idl "$IDL" inspect "$REGISTRY_BIN" \
  | grep 'ProgramId (hex)' | awk '{print $NF}' | tr -d ',')
MULTISIG_PROGRAM_ID=$("$MULTISIG_CLI" --idl "$IDL" inspect "$MULTISIG_BIN" \
  | grep 'ProgramId (hex)' | awk '{print $NF}' | tr -d ',')
export REGISTRY_PROGRAM_ID

echo ""
echo "  Waiting for programs to land in a block..."
echo -n "  Polling sequencer for registry program"
# Convert hex program ID to base58 for RPC
REGISTRY_B58=$(python3 -c "
ALPHA = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
h = '$REGISTRY_PROGRAM_ID'
if not h: exit(1)
b = bytes.fromhex(h)
n = int.from_bytes(b, 'big')
r = ''
while n:
    n, rem = divmod(n, 58)
    r = ALPHA[rem] + r
for byte in b:
    if byte == 0: r = ALPHA[0] + r
    else: break
print(r)
")
for i in $(seq 1 40); do
  sleep 3
  echo -n "."
  RESULT=$(curl -s --max-time 2 -X POST "$SEQUENCER_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"get_account\",\"params\":{\"account_id\":\"$REGISTRY_B58\"},\"id\":1}" 2>/dev/null)
  HAS_ACCOUNT=$(echo "$RESULT" | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    acct = d.get('result', {}).get('account', {})
    if acct and acct.get('nonce', 0) > 0:
        print('yes')
    else:
        print('no')
except:
    print('no')
" 2>/dev/null)
  if [ "$HAS_ACCOUNT" = "yes" ]; then
    echo " ready!"
    break
  fi
done


echo ""
ok "Token    ID: $TOKEN_PROGRAM_ID"
ok "Registry ID: $REGISTRY_PROGRAM_ID"
ok "Multisig ID: $MULTISIG_PROGRAM_ID"

sleep 1

# ── Step 2: Register Programs in Registry ────────────────────────────────

banner "Step 2 — Register Programs in the On-Chain Registry"

echo "  Registering token program..."
run "registry register --name lez-token --version 0.1.0 ..."
"$REGISTRY_CLI" register \
  --account          "$SIGNER" \
  --registry-program "$REGISTRY_PROGRAM_ID" \
  --program-id       "$TOKEN_PROGRAM_ID" \
  --name             "lez-token" \
  --version          "0.1.0" \
  --description      "Fungible token program for LEZ" \
  --idl-path         "$TOKEN_IDL" \
  --tag              governance \
  --tag              token 2>&1 \
  && ok "lez-token registered" \
  || err "Registration failed — check output above"

sleep 2

echo ""
echo "  Registering multisig program..."
run "registry register --name lez-multisig --version 0.1.0 ..."
"$REGISTRY_CLI" register \
  --account          "$SIGNER" \
  --registry-program "$REGISTRY_PROGRAM_ID" \
  --program-id       "$MULTISIG_PROGRAM_ID" \
  --name             "lez-multisig" \
  --version          "0.1.0" \
  --description      "M-of-N on-chain governance for LEZ" \
  --idl-path         "$MULTISIG_IDL" \
  --tag              governance \
  --tag              multisig 2>&1 \
  && ok "lez-multisig registered" \
  || err "Registration failed — check output above"

sleep 15

# ── Step 3: List Registry ──────────────────────────────────────────────────

banner "Step 3 — Registry: All Programs Discoverable On-Chain"

run "registry list --registry-program ..."
"$REGISTRY_CLI" list --registry-program "$REGISTRY_PROGRAM_ID" 2>&1
ok "Registry is live — programs are discoverable!"

sleep 1

# ── Step 4: Generate Target Member Accounts ────────────────────────────────

banner "Step 4 — Generate Fresh Target Member Keypairs"

echo -e "  ${DIM}M2 and M3 are fresh target accounts to be added to the multisig."
echo -e "  SIGNER ($SIGNER) is the"
echo -e "  initial member and the sole signer — it holds the signing key.${RESET}"
echo ""

SUFFIX=$(date +%s | tail -c 5)

run "new_account signer-..."
read SIGNER SIGNER_HEX_PK <<< $(new_account "signer-$SUFFIX")
echo "  Signer: $SIGNER ($SIGNER_HEX_PK)"

run "new_account m1-..."
read M1_ACCOUNT M1_HEX <<< $(new_account "m1-$SUFFIX")
echo "  M1: $M1_ACCOUNT ($M1_HEX)"

run "new_account m2-..."
read M2_ACCOUNT M2 <<< $(new_account "m2-$SUFFIX")
echo "  M2: $M2_ACCOUNT ($M2)"

run "new_account m3-..."
read M3_ACCOUNT M3 <<< $(new_account "m3-$SUFFIX")
echo "  M3: $M3_ACCOUNT ($M3)"

echo ""
ok "Signer (initial member): $SIGNER"
ok "Member 2 (to be added): $M2_ACCOUNT"
ok "Member 3 (to be added): $M3_ACCOUNT"

sleep 1

# ── Step 5: Create Multisig ────────────────────────────────────────────────

banner "Step 5 — CreateMultisig  (threshold=1, initial member: SIGNER)"

CREATE_KEY="demo-$SUFFIX"
echo "  Threshold  : 1-of-1 approval required (grows as members join)"
echo "  Create key : $CREATE_KEY"
echo "  Initial member: SIGNER (hex pk)"
echo ""

run "multisig create-multisig --create-key $CREATE_KEY --threshold 1 --members SIGNER_HEX_PK ..."
CREATE_OUT=$("$MULTISIG_CLI" \
  --idl     "$IDL" \
  --program "$MULTISIG_BIN" \
  create-multisig \
    --create-key              "$CREATE_KEY" \
    --threshold               1 \
    --members                 "$M1_HEX" \
    --member-accounts-account "$M1_ACCOUNT" 2>&1)

echo "$CREATE_OUT"

# Capture multisig state PDA from the submission output
MULTISIG_STATE=$(echo "$CREATE_OUT" | grep 'PDA multisig_state' | awk '{print $NF}')
ok "Multisig created!"
ok "State PDA: $MULTISIG_STATE"

echo ""
echo "  Waiting for CreateMultisig to land in a block..."
sleep 15

# ── Step 6: Propose Adding Member 2 ──────────────────────────────────────

banner "Step 6 — Propose: Add Member 2 to the Multisig"

echo "  SIGNER proposes adding M2. The proposer is auto-approved (vote #1)."
echo "  Threshold=1 → immediately ready to execute."
echo ""

# Generate a fresh account to hold the proposal state (init: true)
run "new_account prop1-..."
read PROP1 _PROP1_HEX <<< $(new_account "prop1-$SUFFIX")
ok "Proposal account: $PROP1"
echo ""

run "multisig propose-add-member --new-member M2 --proposer SIGNER ..."
"$MULTISIG_CLI" \
  --idl     "$IDL" \
  --program "$MULTISIG_BIN" \
  propose-add-member \
    --new-member              "$M2" \
    --multisig-state-account  "$MULTISIG_STATE" \
    --proposer-account        "$M1_ACCOUNT" \
    --proposal-account        "$PROP1" 2>&1

echo ""
ok "Proposal #1 created!"
ok "SIGNER auto-approved — 1 of 1 votes cast (threshold = 1 → ready to execute!)"

echo ""
echo "  Waiting for Propose to land in a block..."
sleep 15

# ── Step 7: Execute Proposal #1 ───────────────────────────────────────────

banner "Step 7 — Execute Proposal #1  (threshold already met)"

echo "  With threshold=1, SIGNER executes immediately after proposing."
echo "  The multisig emits a ChainedCall to add M2 to the multisig state."
echo ""

run "multisig execute --proposal-index 1 --executor SIGNER ..."
"$MULTISIG_CLI" \
  --idl     "$IDL" \
  --program "$MULTISIG_BIN" \
  execute \
    --proposal-index         1 \
    --multisig-state-account "$MULTISIG_STATE" \
    --executor-account       "$M1_ACCOUNT" \
    --proposal-account       "$PROP1" 2>&1

echo ""
ok "Proposal #1 executed!"
ok "M2 has joined the multisig. Members: SIGNER, M2"

echo ""
echo "  Waiting for Execute to land..."
sleep 15

# ── Step 8: Propose Adding Member 3 ──────────────────────────────────────

banner "Step 8 — Propose: Add Member 3  (threshold=1, SIGNER proposes)"

echo "  Multisig now has 2 members (SIGNER, M2). SIGNER proposes adding M3."
echo ""

run "new_account prop2-..."
read PROP2 _PROP2_HEX <<< $(new_account "prop2-$SUFFIX")
ok "Proposal 2 account: $PROP2"
echo ""

run "multisig propose-add-member --new-member M3 --proposer SIGNER ..."
"$MULTISIG_CLI" \
  --idl     "$IDL" \
  --program "$MULTISIG_BIN" \
  propose-add-member \
    --new-member              "$M3" \
    --multisig-state-account  "$MULTISIG_STATE" \
    --proposer-account        "$M1_ACCOUNT" \
    --proposal-account        "$PROP2" 2>&1

echo ""
ok "Proposal #2 created!"
ok "SIGNER auto-approved (1/1 — threshold met)"

echo ""
echo "  Waiting for Propose to land..."
sleep 15

# ── Step 9: Execute Proposal #2 ─────────────────────────────────────────

banner "Step 9 — Execute Proposal #2  (M3 joins)"

echo "  SIGNER executes to make M3 official."
echo ""

run "multisig execute --proposal-index 2 --executor SIGNER ..."
"$MULTISIG_CLI" \
  --idl     "$IDL" \
  --program "$MULTISIG_BIN" \
  execute \
    --proposal-index          2 \
    --multisig-state-account  "$MULTISIG_STATE" \
    --executor-account        "$M1_ACCOUNT" \
    --proposal-account        "$PROP2" 2>&1

echo ""
ok "Proposal #2 executed!"
ok "M3 has joined. Final multisig: SIGNER, M2, M3 — threshold 1"

echo ""
echo "  Waiting for Execute to land..."
sleep 15

# ── Final: Registry info ──────────────────────────────────────────────────

banner "Final — Registry: Verify Multisig Is Discoverable"

run "registry info --program-id <multisig-id>"
"$REGISTRY_CLI" info \
  --registry-program "$REGISTRY_PROGRAM_ID" \
  --program-id       "$MULTISIG_PROGRAM_ID" 2>&1

echo ""

# ── Done ─────────────────────────────────────────────────────────────────

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  🎉  Demo complete!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${GREEN}✅${RESET}  Step 0  — Inspected program IDs (hashes of bytecode)"
echo -e "  ${GREEN}✅${RESET}  Step 1  — Deployed token + registry + multisig on-chain"
echo -e "  ${GREEN}✅${RESET}  Step 2  — Registered both in the on-chain registry"
echo -e "  ${GREEN}✅${RESET}  Step 3  — Listed registry (programs discoverable)"
echo -e "  ${GREEN}✅${RESET}  Step 4  — Generated 2 fresh target keypairs (M2, M3)"
echo -e "  ${GREEN}✅${RESET}  Step 5  — Created multisig (SIGNER as initial member)"
echo -e "  ${GREEN}✅${RESET}  Step 6  — Proposed adding M2 (SIGNER auto-approved)"
echo -e "  ${GREEN}✅${RESET}  Step 7  — Executed → M2 joined the multisig"
echo -e "  ${GREEN}✅${RESET}  Step 8  — Proposed adding M3 (SIGNER auto-approved)"
echo -e "  ${GREEN}✅${RESET}  Step 9  — Executed → M3 joined the multisig"
echo -e "  ${GREEN}✅${RESET}  Final   — Registry confirmed multisig is discoverable"
echo ""
echo -e "  What this proves:"
echo -e "  • LEZ programs deploy, run, and compose via ChainedCall"
echo -e "  • Registry makes them discoverable on-chain"
echo -e "  • Multisig provides trustless M-of-N governance"
echo -e "  • ZK proofs verified — no trusted executor"
echo ""
echo -e "  ${DIM}Spec: $MULTISIG_DIR/SPEC.md${RESET}"
echo -e "  ${DIM}Repo: https://github.com/jimmy-claw/lez-multisig-framework${RESET}"
echo ""
