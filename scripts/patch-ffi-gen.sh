#!/usr/bin/env python3
"""Post-process the spel-client-gen output to fix known upstream gaps.

Called from `make generate-ffi` after spel-client-gen runs.
Remove once the upstream fix lands in spel-client-gen:
  https://github.com/logos-co/spel/pull/209

Usage: scripts/patch-ffi-gen.sh <path/to/multisig.rs> <path/to/ffi_helpers.rs.inc>
"""
import sys
import re

ffi_rs_path = sys.argv[1]
helpers_path = sys.argv[2]

with open(ffi_rs_path) as f:
    content = f.read()

with open(helpers_path) as f:
    helpers = f.read()

# 1. Inject helpers before `static ASYNC_RUNTIME` (only once)
marker = "static ASYNC_RUNTIME"
if marker not in content:
    print(f"ERROR: marker '{marker}' not found in {ffi_rs_path}", file=sys.stderr)
    sys.exit(1)

if "fn parse_bytes32" not in content:
    content = content.replace(marker, helpers + "\n" + marker, 1)
    print("  ✓ parse_create_key / parse_bytes32 helpers injected")
else:
    print("  ✓ helpers already present, skipping injection")

# 2. Replace create_key call sites (old serde_json format and new parse_account_id format)
import re
def replace_create_key(text):
    # Old format: serde_json::from_value
    old = 'let create_key: [u8; 32] = serde_json::from_value(v["create_key"].clone()).map_err(|e| format!("parse error: {}", e))?;'
    new = 'let create_key: [u8; 32] = parse_bytes32(&v["create_key"])?;'
    n = text.count(old)
    text = text.replace(old, new)
    # New format: parse_account_id
    old2 = 'let create_key = parse_account_id(v["create_key"].as_str().ok_or("expected string for [u8; 32]")?)?;'
    new2 = 'let create_key: [u8; 32] = parse_bytes32(&v["create_key"])?;'
    n2 = text.count(old2)
    text = text.replace(old2, new2)
    total = n + n2
    if total:
        print(f"  ✓ create_key: replaced {total} call site(s)")
    return text
content = replace_create_key(content)

# 3. Replace members per-item call (old and new formats)
old = '.map(|item| Ok(serde_json::from_value(item.clone()).map_err(|e| format!("parse error: {}", e))?))'
new = '.map(|item| parse_bytes32(item))'
n = content.count(old)
content = content.replace(old, new)
# New format: parse_account_id per item
old2 = '.iter().map(|item| Ok(parse_account_id(item.as_str().ok_or("expected string for [u8; 32]")?)?)).collect::<Result<Vec<_>, String>>()?;'
new2 = '.iter().map(|item| parse_bytes32(item)).collect::<Result<Vec<_>, String>>()?;'
n2 = content.count(old2)
content = content.replace(old2, new2)
if n + n2:
    print(f"  ✓ members/pda_seeds: replaced {n + n2} call site(s)")

# 4. Replace new_member call site (old and new formats)
old = 'let new_member = serde_json::from_value(v["new_member"].clone()).map_err(|e| format!("parse error: {}", e))?;'
new = 'let new_member: [u8; 32] = parse_bytes32(&v["new_member"])?;'
n = content.count(old)
content = content.replace(old, new)
old2 = 'let new_member = parse_account_id(v["new_member"].as_str().ok_or("expected string for [u8; 32]")?)?;'
new2 = 'let new_member: [u8; 32] = parse_bytes32(&v["new_member"])?;'
n2 = content.count(old2)
content = content.replace(old2, new2)
if n + n2:
    print(f"  ✓ new_member: replaced {n + n2} call site(s)")

# 5. Replace member call site (old and new formats)
old = 'let member = serde_json::from_value(v["member"].clone()).map_err(|e| format!("parse error: {}", e))?;'
new = 'let member: [u8; 32] = parse_bytes32(&v["member"])?;'
n = content.count(old)
content = content.replace(old, new)
old2 = 'let member = parse_account_id(v["member"].as_str().ok_or("expected string for [u8; 32]")?)?;'
new2 = 'let member: [u8; 32] = parse_bytes32(&v["member"])?;'
n2 = content.count(old2)
content = content.replace(old2, new2)
if n + n2:
    print(f"  ✓ member: replaced {n + n2} call site(s)")

# 6. Derive member_accounts from members instead of requiring a separate JSON field.
# The members instruction arg and the member_accounts transaction slots are the same
# data — [u8;32] keys. The UI only sends `members`, so derive the account list from it.
# Old format: single-line assignment
old = (
    'let member_accounts: Vec<AccountId> = v["member_accounts"].as_array()\n'
    '        .ok_or("missing member_accounts")?\n'
    '        .iter().map(|a| parse_account_id(a.as_str().ok_or("expected string")?)).collect::<Result<Vec<_>,_>>()?;'
)
new = 'let member_accounts: Vec<AccountId> = members.iter().map(|m| AccountId::new(*m)).collect();'
n = content.count(old)
content = content.replace(old, new)
# New format (4b8a71c): conditional block — else branch has type error (members is Vec<[u8;32]>)
old2 = (
    'let member_accounts: Vec<AccountId> = if v["member_accounts"].is_array() {\n'
    '        v["member_accounts"].as_array().unwrap()\n'
    '            .iter().map(|a| parse_account_id(a.as_str().ok_or("expected string")?)).collect::<Result<Vec<_>,_>>()?\n'
    '    } else {\n'
    '        members.clone()\n'
    '    };'
)
new2 = 'let member_accounts: Vec<AccountId> = members.iter().map(|m| AccountId::new(*m)).collect();'
n2 = content.count(old2)
content = content.replace(old2, new2)
if n + n2:
    print(f"  ✓ member_accounts: derived from members ({n + n2} site(s))")

# 7. Add block-inclusion polling after every send_transaction call.
# The CLI does this via wallet::poller::TxPoller; the raw FFI just fires-and-forgets.
old = (
    '        wallet.sequencer_client.send_transaction(common::transaction::NSSATransaction::Public(tx)).await\n'
    '            .map_err(|e| format!("submit: {}", e))\n'
    '            .map(|r| hex::encode(r.0))\n'
    '    })?;'
)
new = (
    '        let raw_hash = wallet.sequencer_client.send_transaction(common::transaction::NSSATransaction::Public(tx)).await\n'
    '            .map_err(|e| format!("submit: {}", e))?;\n'
    '        let tx_hash_hex = hex::encode(raw_hash.0);\n'
    '        let poller = wallet::poller::TxPoller::new(wallet.config(), wallet.sequencer_client.clone());\n'
    '        poller.poll_tx(raw_hash).await.map_err(|e| format!("confirmation: {}", e))?;\n'
    '        Ok::<String, String>(tx_hash_hex)\n'
    '    })?;'
)
n = content.count(old)
content = content.replace(old, new)
if n:
    print(f"  ✓ send_transaction: added block-inclusion polling ({n} site(s))")
else:
    print("  ⚠ send_transaction polling patch did not match — check generated code", file=sys.stderr)

# 8. Verify fetch_proposal FFI function is present.
# As of spel-client-gen commit 59b9c94, the generator correctly emits:
#   - Borsh type definitions from idl.types (ProposalStatus, ConfigAction enums)
#   - ProposalState struct with proper field types
#   - fetch_proposal_impl with correct JSON serialization (hex for bytes, match for enums)
# This step is now a sanity check only; no injection needed for up-to-date generators.
FETCH_PROPOSAL_MARKER = "pub extern \"C\" fn multisig_program_fetch_proposal"
if FETCH_PROPOSAL_MARKER not in content:
    print("  ⚠ fetch_proposal function missing — generator may be outdated; run make install-tools", file=sys.stderr)
else:
    print("  ✓ fetch_proposal present (generator handles struct and JSON serialization)")

with open(ffi_rs_path, "w") as f:
    f.write(content)

print("  ✓ patch-ffi-gen done")
