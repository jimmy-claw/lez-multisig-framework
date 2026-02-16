// Deposit handler — deposits funds into the vault (anyone can call)

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};

/// Handle Deposit instruction
/// 
/// Expected accounts:
/// - accounts[0]: vault (PDA) — the treasury vault
/// 
/// Authorization: anyone can deposit
pub fn handle(
    accounts: &[AccountWithMetadata],
    amount: u128,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    // Parse accounts
    assert!(accounts.len() >= 1, "Deposit requires vault account");
    
    let vault_account = &accounts[0];
    
    // Build post state - increase balance
    let mut vault_post = vault_account.account.clone();
    vault_post.balance = vault_post.balance.saturating_add(amount);
    
    let post_state = AccountPostState::new(vault_post);

    (vec![post_state], vec![])
}
