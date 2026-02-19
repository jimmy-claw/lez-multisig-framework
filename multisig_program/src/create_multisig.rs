// CreateMultisig handler — initializes a new M-of-N multisig

use nssa_core::account::{Account, AccountWithMetadata};
use nssa_core::program::{AccountPostState, ChainedCall};
use multisig_core::MultisigState;

/// Handle CreateMultisig instruction
/// 
/// Expected accounts:
/// - accounts[0]: multisig_state (PDA, uninitialized) — derived from (program_id, create_key)
/// 
/// Authorization: anyone can create a new multisig (create_key makes PDA unique)
pub fn handle(
    accounts: &[AccountWithMetadata],
    create_key: &[u8; 32],
    threshold: u8,
    members: &[[u8; 32]],
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    // Validate inputs
    assert!(!members.is_empty(), "Multisig must have at least one member");
    assert!(threshold >= 1, "Threshold must be at least 1");
    assert!((threshold as usize) <= members.len(), "Threshold cannot exceed member count");
    assert!(members.len() <= 10, "Maximum 10 members for PoC");

    // Verify account is uninitialized (default)
    assert!(!accounts.is_empty(), "CreateMultisig requires multisig_state account");
    assert!(
        accounts[0].account == Account::default(),
        "Multisig state account must be uninitialized"
    );

    // Create multisig state with create_key for future reference
    let state = MultisigState::new(*create_key, threshold, members.to_vec());
    
    // Initialize multisig state account
    let mut multisig_account = Account::default();
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_account.data = state_bytes.try_into().unwrap();
    
    (vec![AccountPostState::new_claimed(multisig_account)], vec![])
}
