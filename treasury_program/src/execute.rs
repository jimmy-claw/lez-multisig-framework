// Execute handler — executes a transaction when M-of-N threshold is met

use borsh::BorshSerialize;
use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, ProgramId};
use treasury_core::MultisigState;

/// Handle Execute instruction
/// 
/// Expected accounts:
/// - accounts[0]: multisig_state (PDA) — contains threshold, members, nonce
/// - accounts[1]: vault (PDA) — the treasury vault to transfer from
/// - accounts[2..]: authorized accounts — the signers (must have is_authorized = true)
/// 
/// Authorization: M distinct members must be authorized
pub fn handle(
    accounts: &[AccountWithMetadata],
    _recipient: &nssa_core::account::AccountId,
    amount: u128,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    // Parse accounts
    assert!(accounts.len() >= 2, "Execute requires multisig_state and vault accounts");
    
    let multisig_account = &accounts[0];
    let vault_account = &accounts[1];
    
    // Get authorized signers from accounts with is_authorized = true
    let authorized_signers: Vec<[u8; 32]> = accounts[2..]
        .iter()
        .filter(|acc| acc.is_authorized)
        .map(|acc| {
            // AccountId is 32 bytes - extract the key bytes
            let id_bytes: Vec<u8> = acc.account_id.value().clone().into();
            let mut key = [0u8; 32];
            key.copy_from_slice(&id_bytes[..32]);
            key
        })
        .collect();
    
    assert!(!authorized_signers.is_empty(), "No authorized signers");
    
    // Deserialize multisig state
    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");
    
    // Check threshold
    let valid_signers = state.count_valid_signers(&authorized_signers);
    assert!(
        valid_signers >= state.threshold as usize,
        "Insufficient signatures: need {}, got {}",
        state.threshold,
        valid_signers
    );
    
    // Check vault balance
    assert!(
        vault_account.account.balance >= amount,
        "Insufficient balance: have {}, need {}",
        vault_account.account.balance,
        amount
    );
    
    // Build post states
    let mut post_states = Vec::new();
    
    // Update multisig state (increment nonce)
    let mut new_state = state.clone();
    new_state.nonce += 1;
    
    let mut multisig_post = multisig_account.account.clone();
    let state_bytes = borsh::to_vec(&new_state).unwrap();
    multisig_post.data = state_bytes.try_into().unwrap();
    post_states.push(AccountPostState::new(multisig_post));
    
    // Update vault (decrease balance)
    let mut vault_post = vault_account.account.clone();
    vault_post.balance = vault_post.balance.saturating_sub(amount);
    post_states.push(AccountPostState::new(vault_post));
    
    // Emit chained call to transfer (placeholder - would integrate with token program)
    // Using zeroed program ID - real implementation would call token program
    let zero_program_id = ProgramId::default();
    let chained_calls = vec![ChainedCall {
        program_id: zero_program_id,
        instruction_data: vec![],
        pre_states: vec![],
        pda_seeds: vec![],
    }];

    (post_states, chained_calls)
}
