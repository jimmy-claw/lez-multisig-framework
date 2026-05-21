#!/usr/bin/env python3
"""Post-process the spel-client-gen output to fix known upstream gaps.

Called from `make generate-ffi` after spel-client-gen runs.
Remove once the upstream fix lands in spel-client-gen:
  https://github.com/logos-co/spel/pull/209

Usage: scripts/patch-ffi-gen.sh <path/to/multisig.rs>
"""
import sys

ffi_rs_path = sys.argv[1]

with open(ffi_rs_path) as f:
    content = f.read()

# 1. Derive member_accounts from members instead of requiring a separate JSON field.
# The members instruction arg and the member_accounts transaction slots are the same
# data — [u8;32] keys. The UI only sends `members`, so derive the account list from it.
# The generator emits a conditional that falls through to `members.clone()` in the else
# branch, but members is Vec<[u8;32]> while member_accounts is Vec<AccountId> — type error.
old = (
    'let member_accounts: Vec<AccountId> = if v["member_accounts"].is_array() {\n'
    '        v["member_accounts"].as_array().unwrap()\n'
    '            .iter().map(|a| parse_account_id(a.as_str().ok_or("expected string")?)).collect::<Result<Vec<_>,_>>()?\n'
    '    } else {\n'
    '        members.clone()\n'
    '    };'
)
new = 'let member_accounts: Vec<AccountId> = members.iter().map(|m| AccountId::new(*m)).collect();'
n = content.count(old)
content = content.replace(old, new)
if n:
    print(f"  ✓ member_accounts: derived from members ({n} site(s))")
else:
    print("  ⚠ member_accounts patch did not match — check generated code", file=sys.stderr)

# 2. Verify fetch_proposal FFI function is present.
# As of spel-client-gen commit 59b9c94+, the generator correctly emits Borsh type
# definitions from idl.types and fetch_proposal_impl with correct JSON serialization.
FETCH_PROPOSAL_MARKER = 'pub extern "C" fn multisig_program_fetch_proposal'
if FETCH_PROPOSAL_MARKER not in content:
    print("  ⚠ fetch_proposal function missing — generator may be outdated; run make install-tools", file=sys.stderr)
else:
    print("  ✓ fetch_proposal present (generator handles struct and JSON serialization)")

with open(ffi_rs_path, "w") as f:
    f.write(content)

print("  ✓ patch-ffi-gen done")
