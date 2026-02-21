// CreateMultisig handler — initializes a new M-of-N multisig

use nssa_core::account::{Account, AccountWithMetadata};
use nssa_core::program::{AccountPostState, ChainedCall};
use multisig_core::MultisigState;

/// Handle CreateMultisig instruction
/// 
/// Expected accounts:
/// - accounts[0]: multisig_state (PDA, uninitialized) — derived from (program_id, create_key)
/// - accounts[1..N+1]: member accounts (must be Account::default() = uninitialized/fresh)
///
/// All member accounts are claimed by the multisig program during creation.
/// This means members must use fresh keypairs dedicated to this multisig.
/// After claiming, member accounts have program_owner = multisig_program_id,
/// which allows them to be included in subsequent instructions without
/// triggering NSSA validation rule 7.
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

    // We need multisig_state + all member accounts
    assert!(
        accounts.len() >= 1 + members.len(),
        "CreateMultisig requires multisig_state + {} member accounts, got {}",
        members.len(),
        accounts.len()
    );

    // Verify multisig state account is uninitialized
    assert!(
        accounts[0].account == Account::default(),
        "Multisig state account must be uninitialized"
    );

    // Verify each member account is uninitialized and matches the member list
    for (i, member_id) in members.iter().enumerate() {
        let member_account = &accounts[1 + i];
        assert!(
            member_account.account == Account::default(),
            "Member account {} must be uninitialized (fresh keypair required)",
            i
        );
        assert_eq!(
            member_account.account_id.value(),
            member_id,
            "Member account {} ID does not match member list",
            i
        );
    }

    // Create multisig state
    let state = MultisigState::new(*create_key, threshold, members.to_vec());
    
    let mut multisig_account = Account::default();
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_account.data = state_bytes.try_into().unwrap();
    
    // Build post_states: claim multisig_state + all member accounts
    let mut post_states = vec![AccountPostState::new_claimed(multisig_account)];
    
    for i in 0..members.len() {
        // Claim member account (empty data, just establishing ownership)
        post_states.push(AccountPostState::new_claimed(accounts[1 + i].account.clone()));
    }
    
    (post_states, vec![])
}
