// ChangeThreshold handler — changes the M-of-N threshold (requires threshold signatures)

use borsh::BorshSerialize;
use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};
use treasury_core::MultisigState;

/// Handle ChangeThreshold instruction
/// 
/// Expected accounts:
/// - accounts[0]: multisig_state (PDA) — contains threshold, members, nonce
/// - accounts[1..]: authorized accounts — the signers (must have is_authorized = true)
/// 
/// Authorization: M distinct members must be authorized
pub fn handle(
    accounts: &[AccountWithMetadata],
    new_threshold: u8,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    // Parse accounts
    assert!(accounts.len() >= 2, "ChangeThreshold requires multisig_state and authorized accounts");
    
    let multisig_account = &accounts[0];
    
    // Get authorized signers
    let authorized_signers: Vec<[u8; 32]> = accounts[1..]
        .iter()
        .filter(|acc| acc.is_authorized)
        .map(|acc| {
            let id_bytes: Vec<u8> = acc.account_id.value().clone().into();
            let mut key = [0u8; 32];
            key.copy_from_slice(&id_bytes[..32]);
            key
        })
        .collect();
    
    // Deserialize multisig state
    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let mut state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");
    
    // Check threshold
    let valid_signers = state.count_valid_signers(&authorized_signers);
    assert!(
        valid_signers >= state.threshold as usize,
        "Insufficient signatures: need {}, got {}",
        state.threshold,
        valid_signers
    );
    
    // Validate new threshold
    assert!(new_threshold >= 1, "Threshold must be at least 1");
    assert!(
        new_threshold <= state.member_count,
        "Threshold cannot exceed member count"
    );
    
    // Update threshold
    state.threshold = new_threshold;
    state.nonce += 1;
    
    // Build post state
    let mut multisig_post = multisig_account.account.clone();
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_post.data = state_bytes.try_into().unwrap();

    (vec![AccountPostState::new(multisig_post)], vec![])
}
