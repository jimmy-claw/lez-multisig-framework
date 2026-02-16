// CreateMultisig handler — initializes a new M-of-N multisig

use borsh::BorshSerialize;
use nssa_core::account::{Account, AccountWithMetadata};
use nssa_core::program::{AccountPostState, ChainedCall};
use treasury_core::MultisigState;

/// Handle CreateMultisig instruction
/// 
/// Expected accounts:
/// - accounts[0]: multisig_state (PDA, uninitialized) — will store threshold + members
/// - accounts[1]: vault (PDA, uninitialized) — the treasury vault
/// 
/// Authorization: anyone can create a new multisig
pub fn handle(
    accounts: &[AccountWithMetadata],
    threshold: u8,
    members: &[[u8; 32]],
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    // Validate inputs
    assert!(!members.is_empty(), "Multisig must have at least one member");
    assert!(threshold >= 1, "Threshold must be at least 1");
    assert!((threshold as usize) <= members.len(), "Threshold cannot exceed member count");
    assert!(members.len() <= 10, "Maximum 10 members for PoC");

    // Create multisig state
    let state = MultisigState::new(threshold, members.to_vec());
    
    // Build post states
    let mut post_states = Vec::new();
    
    // Initialize multisig state account (use account 0 as passed in)
    assert!(!accounts.is_empty(), "CreateMultisig requires at least multisig_state account");
    let mut multisig_account = Account::default();
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_account.data = state_bytes.try_into().unwrap();
    
    post_states.push(AccountPostState::new_claimed(multisig_account));
    
    // Initialize vault account (if provided)
    if accounts.len() > 1 {
        let vault_account = accounts[1].account.clone();
        post_states.push(AccountPostState::new(vault_account));
    }

    (post_states, vec![])
}
