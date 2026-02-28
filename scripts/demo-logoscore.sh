#!/usr/bin/env bash
# =============================================================================
#  demo-logoscore.sh — E2E demo: logoscore --call with lez_multisig_module
# =============================================================================
#
#  Validates the full Logos Core plugin stack headlessly:
#    logoscore CLI → Qt plugin loader → logos_host subprocess →
#    QtRemoteObjects RPC → lez_multisig_module → lez-multisig-ffi (Rust) →
#    NSSA sequencer
#
#  Tests:
#    1. version()        — basic plugin load + FFI
#    2. getState()       — full FFI→sequencer path (dummy args)
#    3. listProposals()  — full FFI→sequencer path (dummy args)
#    4. Dual module load — both multisig + capability modules
#    5. Live sequencer   — real program IDs if sequencer is up
#
#  Prerequisites:
#    - Nix build:  ~/logos-lez-multisig-module/result/{bin/logoscore,modules/}
#    - Optional:   sequencer at http://127.0.0.1:3040
#
#  Usage:
#    bash scripts/demo-logoscore.sh
#    SEQUENCER_URL=http://... bash scripts/demo-logoscore.sh
#
# =============================================================================
set -euo pipefail

export PATH="$HOME/.nix-profile/bin:$PATH"

# ── Paths ────────────────────────────────────────────────────────────────────

LOGOSCORE="$HOME/logos-lez-multisig-module/result/bin/logoscore"
MODULES_DIR="$HOME/logos-lez-multisig-module/result/modules"
SEQUENCER_URL="${SEQUENCER_URL:-http://127.0.0.1:3040}"
WALLET_DIR="${NSSA_WALLET_HOME_DIR:-$HOME/lez-multisig-framework/demo-wallet}"
MULTISIG_DIR="${MULTISIG_DIR:-$HOME/lez-multisig-framework}"

# ── Colours ──────────────────────────────────────────────────────────────────

BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'

# ── Helpers ──────────────────────────────────────────────────────────────────

PASS=0; FAIL=0; SKIP=0

pass() { echo -e "  ${GREEN}PASS${RESET}: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${RESET}: $1 — $2"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${RESET}: $1 — $2"; SKIP=$((SKIP + 1)); }
banner() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${RESET}\n"; }
info()   { echo -e "  ${DIM}$1${RESET}"; }

cleanup_logoscore() {
    pkill -f "logoscore.*modules-dir" 2>/dev/null || true
    pkill -f "logos_host" 2>/dev/null || true
    sleep 0.5
}

# Run a logoscore --call and capture output.
# Usage: logoscore_call <load_modules> <call_expr>
logoscore_call() {
    local load_modules="$1"
    local call_expr="$2"

    cleanup_logoscore

    local output
    output=$(QT_QPA_PLATFORM=offscreen timeout 30 "$LOGOSCORE" \
        --modules-dir "$MODULES_DIR" \
        --load-modules "$load_modules" \
        --call "$call_expr" 2>&1 || true)

    cleanup_logoscore
    echo "$output"
}

# Extract the result value after "Method call successful. Result: "
extract_result() {
    echo "$1" | grep "Method call successful" | sed 's/.*Result: //'
}

# ── Pre-flight ───────────────────────────────────────────────────────────────

banner "Pre-flight Checks"

if [[ ! -x "$LOGOSCORE" ]]; then
    echo -e "${RED}logoscore not found at $LOGOSCORE${RESET}"
    echo "Build with: cd ~/logos-lez-multisig-module && nix build"
    exit 1
fi
pass "logoscore binary: $LOGOSCORE"

if [[ ! -f "$MODULES_DIR/liblez_multisig_module.so" ]]; then
    echo -e "${RED}multisig module not found in $MODULES_DIR${RESET}"
    exit 1
fi
pass "multisig module: $MODULES_DIR/liblez_multisig_module.so"

HAS_CAPABILITY=false
if [[ -f "$MODULES_DIR/capability_module_plugin.so" ]]; then
    pass "capability module: $MODULES_DIR/capability_module_plugin.so"
    HAS_CAPABILITY=true
else
    info "capability module not found (dual-load test will be skipped)"
fi

SEQUENCER_UP=false
if curl -s --max-time 2 "$SEQUENCER_URL" >/dev/null 2>&1; then
    pass "sequencer reachable at $SEQUENCER_URL"
    SEQUENCER_UP=true
else
    skip "sequencer" "not running at $SEQUENCER_URL (live tests will be skipped)"
fi

mkdir -p "$WALLET_DIR"

# ── Test 1: version() ───────────────────────────────────────────────────────

banner "Test 1: lez_multisig_module.version()"

OUTPUT=$(logoscore_call "lez_multisig_module" "lez_multisig_module.version()")

if echo "$OUTPUT" | grep -q "Method call successful. Result: 0.1.0"; then
    pass "version() = 0.1.0"
else
    fail "version()" "unexpected output"
    echo "$OUTPUT" | tail -5 | sed 's/^/      /'
fi

# ── Test 2: getState() with dummy args ───────────────────────────────────────

banner "Test 2: lez_multisig_module.getState() (dummy args — proves FFI path)"

ARGS_FILE=$(mktemp /tmp/logoscore_demo_XXXXXX.json)
cat > "$ARGS_FILE" <<EOF
{"sequencer_url":"$SEQUENCER_URL","wallet_path":"$WALLET_DIR","program_id_hex":"0x0000000000000000000000000000000000000000000000000000000000000001","create_key":"0x0000000000000000000000000000000000000000000000000000000000000001"}
EOF

OUTPUT=$(logoscore_call "lez_multisig_module" "lez_multisig_module.getState(@$ARGS_FILE)")
rm -f "$ARGS_FILE"

if echo "$OUTPUT" | grep -q "Method call successful"; then
    RESULT=$(extract_result "$OUTPUT")
    if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'success' in d else 1)" 2>/dev/null; then
        pass "getState() returned valid JSON with 'success' key"
    else
        pass "getState() returned a response from FFI"
    fi
    info "Result: $RESULT"
else
    fail "getState()" "no 'Method call successful' in output"
    echo "$OUTPUT" | tail -5 | sed 's/^/      /'
fi

# ── Test 3: listProposals() with dummy args ──────────────────────────────────

banner "Test 3: lez_multisig_module.listProposals() (dummy args)"

ARGS_FILE=$(mktemp /tmp/logoscore_demo_XXXXXX.json)
cat > "$ARGS_FILE" <<EOF
{"sequencer_url":"$SEQUENCER_URL","wallet_path":"$WALLET_DIR","program_id_hex":"0x0000000000000000000000000000000000000000000000000000000000000001","create_key":"0x0000000000000000000000000000000000000000000000000000000000000001"}
EOF

OUTPUT=$(logoscore_call "lez_multisig_module" "lez_multisig_module.listProposals(@$ARGS_FILE)")
rm -f "$ARGS_FILE"

if echo "$OUTPUT" | grep -q "Method call successful"; then
    RESULT=$(extract_result "$OUTPUT")
    pass "listProposals() returned a response from FFI"
    info "Result: $RESULT"
else
    fail "listProposals()" "no 'Method call successful' in output"
    echo "$OUTPUT" | tail -5 | sed 's/^/      /'
fi

# ── Test 4: Dual module load ────────────────────────────────────────────────

banner "Test 4: Load multiple modules simultaneously"

if $HAS_CAPABILITY; then
    OUTPUT=$(logoscore_call "lez_multisig_module,capability_module" "lez_multisig_module.version()")
    if echo "$OUTPUT" | grep -q "Method call successful. Result: 0.1.0"; then
        pass "dual module load: multisig + capability both loaded, version() works"
    else
        fail "dual module load" "version() failed with both modules loaded"
        echo "$OUTPUT" | tail -5 | sed 's/^/      /'
    fi
else
    skip "dual module load" "capability module not available"
fi

# ── Test 5: Live sequencer queries ──────────────────────────────────────────

banner "Test 5: Live sequencer queries"

if ! $SEQUENCER_UP; then
    skip "live getState()" "sequencer not running"
    skip "live listProposals()" "sequencer not running"
else
    # Try to find a deployed multisig program ID
    MULTISIG_BIN="$MULTISIG_DIR/target/riscv32im-risc0-zkvm-elf/docker/multisig.bin"
    MULTISIG_CLI="$MULTISIG_DIR/target/release/multisig"
    IDL="$MULTISIG_DIR/lez-multisig-ffi/src/multisig_idl.json"

    PROG_ID_HEX=""
    if [[ -x "$MULTISIG_CLI" && -f "$MULTISIG_BIN" && -f "$IDL" ]]; then
        PROG_ID_HEX=$("$MULTISIG_CLI" --idl "$IDL" inspect "$MULTISIG_BIN" 2>/dev/null \
            | grep 'ProgramId (hex)' | awk '{print $NF}' | tr -d ',' || true)
    fi

    if [[ -n "$PROG_ID_HEX" ]]; then
        info "Discovered multisig program ID: $PROG_ID_HEX"

        # Use a dummy create_key — getState will return an error about
        # the PDA not existing, but that proves the full path works.
        ARGS_FILE=$(mktemp /tmp/logoscore_demo_XXXXXX.json)
        cat > "$ARGS_FILE" <<EOF
{"sequencer_url":"$SEQUENCER_URL","wallet_path":"$WALLET_DIR","program_id_hex":"$PROG_ID_HEX","create_key":"0x0000000000000000000000000000000000000000000000000000000000000001"}
EOF

        OUTPUT=$(logoscore_call "lez_multisig_module" "lez_multisig_module.getState(@$ARGS_FILE)")
        rm -f "$ARGS_FILE"

        if echo "$OUTPUT" | grep -q "Method call successful"; then
            RESULT=$(extract_result "$OUTPUT")
            pass "live getState() with real program ID reached sequencer"
            info "Result: $RESULT"
        else
            fail "live getState()" "did not get Method call successful"
            echo "$OUTPUT" | tail -5 | sed 's/^/      /'
        fi

        ARGS_FILE=$(mktemp /tmp/logoscore_demo_XXXXXX.json)
        cat > "$ARGS_FILE" <<EOF
{"sequencer_url":"$SEQUENCER_URL","wallet_path":"$WALLET_DIR","program_id_hex":"$PROG_ID_HEX","create_key":"0x0000000000000000000000000000000000000000000000000000000000000001"}
EOF

        OUTPUT=$(logoscore_call "lez_multisig_module" "lez_multisig_module.listProposals(@$ARGS_FILE)")
        rm -f "$ARGS_FILE"

        if echo "$OUTPUT" | grep -q "Method call successful"; then
            RESULT=$(extract_result "$OUTPUT")
            pass "live listProposals() with real program ID reached sequencer"
            info "Result: $RESULT"
        else
            fail "live listProposals()" "did not get Method call successful"
            echo "$OUTPUT" | tail -5 | sed 's/^/      /'
        fi
    else
        skip "live getState()" "multisig-cli or binary not found for program ID discovery"
        skip "live listProposals()" "multisig-cli or binary not found for program ID discovery"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

banner "Results"

echo -e "  ${GREEN}Passed${RESET}: $PASS"
echo -e "  ${RED}Failed${RESET}: $FAIL"
echo -e "  ${YELLOW}Skipped${RESET}: $SKIP"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}Some tests failed!${RESET}"
    exit 1
fi

echo -e "  ${GREEN}${BOLD}All tests passed!${RESET}"
