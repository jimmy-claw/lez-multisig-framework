# LEZ Multisig Demo — CLI Runbook

Manual commands for a live demo. Run each block step-by-step.

## Setup

```bash
export LSSA_DIR=$HOME/lssa
export MULTISIG_DIR=$HOME/lez-multisig-framework
export REGISTRY_DIR=$HOME/lez-registry
export NSSA_WALLET_HOME_DIR=$LSSA_DIR/wallet/configs/debug

WALLET="$LSSA_DIR/target/release/wallet"
MULTISIG="$MULTISIG_DIR/target/debug/multisig"
REGISTRY="$REGISTRY_DIR/target/debug/registry"
IDL="$MULTISIG_DIR/lez-multisig-ffi/src/multisig_idl.json"
TOKEN_BIN="$LSSA_DIR/artifacts/program_methods/token.bin"
REGISTRY_BIN="$REGISTRY_DIR/target/riscv32im-risc0-zkvm-elf/docker/registry.bin"
MULTISIG_BIN="$MULTISIG_DIR/target/riscv32im-risc0-zkvm-elf/docker/multisig.bin"
TOKEN_IDL="$REGISTRY_DIR/registry-idl.json"
MULTISIG_IDL="$MULTISIG_DIR/lez-multisig-ffi/src/multisig_idl.json"
```

## 0. Reset sequencer (clean state)

```bash
pkill -f sequencer_runner || true; sleep 2
rm -rf $LSSA_DIR/rocksdb $LSSA_DIR/mempool
rm -f $NSSA_WALLET_HOME_DIR/storage.json
cd $LSSA_DIR && nohup RUST_LOG=info ./target/release/sequencer_runner \
  ./sequencer_runner/configs/debug/ > /tmp/seq.log 2>&1 &
sleep 3 && curl -s http://127.0.0.1:3040/ > /dev/null && echo "Ready"

# Start mock Codex (for IDL upload)
nohup python3 $MULTISIG_DIR/scripts/mock-codex.py > /tmp/mock-codex.log 2>&1 &
```

## 1. Inspect & capture program IDs

```bash
$MULTISIG --idl $IDL inspect $TOKEN_BIN
$MULTISIG --idl $IDL inspect $REGISTRY_BIN
$MULTISIG --idl $IDL inspect $MULTISIG_BIN

TOKEN_ID=$($MULTISIG --idl $IDL inspect $TOKEN_BIN | grep 'ProgramId (hex)' | awk '{print $NF}' | tr -d ',')
REGISTRY_ID=$($MULTISIG --idl $IDL inspect $REGISTRY_BIN | grep 'ProgramId (hex)' | awk '{print $NF}' | tr -d ',')
MULTISIG_ID=$($MULTISIG --idl $IDL inspect $MULTISIG_BIN | grep 'ProgramId (hex)' | awk '{print $NF}' | tr -d ',')
export REGISTRY_PROGRAM_ID=$REGISTRY_ID
```

## 2. Deploy programs

```bash
echo "demo" | $WALLET deploy-program $TOKEN_BIN
$WALLET deploy-program $REGISTRY_BIN
$WALLET deploy-program $MULTISIG_BIN
sleep 10  # wait for deploy txs to land
```

## 3. Create signer account

```bash
$WALLET account new public --label signer
# Note the account_id (base58) and set:
SIGNER="<base58 from output>"
SIGNER_HEX=$(python3 -c "
ALPHA='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
s='$SIGNER'; n=0
for c in s: n=n*58+ALPHA.index(c)
print(n.to_bytes(32,'big').hex())")
```

## 4. Register programs in registry

```bash
$REGISTRY register \
  --account $SIGNER \
  --registry-program $REGISTRY_ID \
  --program-id $TOKEN_ID \
  --name lez-token --version 0.1.0 \
  --description "Fungible token program for LEZ" \
  --idl-path $TOKEN_IDL \
  --tag token

# Wait for confirmation, then:

$REGISTRY register \
  --account $SIGNER \
  --registry-program $REGISTRY_ID \
  --program-id $MULTISIG_ID \
  --name lez-multisig --version 0.1.0 \
  --description "M-of-N on-chain governance for LEZ" \
  --idl-path $MULTISIG_IDL \
  --tag governance --tag multisig
```

## 5. List registry

```bash
$REGISTRY list --registry-program $REGISTRY_ID
```

## 6. Create member accounts

```bash
$WALLET account new public --label m1
# → M1="<base58>", M1_HEX="<hex>"

$WALLET account new public --label m2
# → M2="<base58>", M2_HEX="<hex>"

$WALLET account new public --label m3
# → M3="<base58>", M3_HEX="<hex>"

# Helper to convert base58 → hex:
# python3 -c "ALPHA='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'; s='<B58>'; n=0
# for c in s: n=n*58+ALPHA.index(c)
# print(n.to_bytes(32,'big').hex())"
```

## 7. Create multisig

```bash
$MULTISIG --idl $IDL --program $MULTISIG_BIN \
  create-multisig \
    --create-key demo-2026 \
    --threshold 1 \
    --members $M1_HEX \
    --member-accounts-account $M1

# Note the "PDA multisig_state" from output:
MULTISIG_STATE="<pda from output>"
# Wait for confirmation
```

## 8. Propose adding M2

```bash
$WALLET account new public --label prop1
PROP1="<base58>"

$MULTISIG --idl $IDL --program $MULTISIG_BIN \
  propose-add-member \
    --new-member $M2_HEX \
    --multisig-state-account $MULTISIG_STATE \
    --proposer-account $M1 \
    --proposal-account $PROP1
# Wait for confirmation
```

## 9. Execute proposal #1

```bash
$MULTISIG --idl $IDL --program $MULTISIG_BIN \
  execute \
    --proposal-index 1 \
    --multisig-state-account $MULTISIG_STATE \
    --executor-account $M1 \
    --proposal-account $PROP1
# M2 is now a member!
```

## 10. Propose + execute adding M3

```bash
$WALLET account new public --label prop2
PROP2="<base58>"

$MULTISIG --idl $IDL --program $MULTISIG_BIN \
  propose-add-member \
    --new-member $M3_HEX \
    --multisig-state-account $MULTISIG_STATE \
    --proposer-account $M1 \
    --proposal-account $PROP2

# Wait, then execute:
$MULTISIG --idl $IDL --program $MULTISIG_BIN \
  execute \
    --proposal-index 2 \
    --multisig-state-account $MULTISIG_STATE \
    --executor-account $M1 \
    --proposal-account $PROP2
```

## 11. Verify in registry

```bash
$REGISTRY info --registry-program $REGISTRY_ID --program-id $MULTISIG_ID
```

## Tips

- Watch sequencer: `tail -f /tmp/seq.log`
- All account IDs from wallet are base58; convert to hex for `--members`
- `--dry-run` on any command shows what would be submitted without sending
- If tx fails: check seq.log for `InvalidProgramBehavior` or `ProgramExecutionFailed`
