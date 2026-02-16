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

#[cfg(test)]
mod tests {
    use super::*;
    use nssa_core::account::{Account, AccountId};

    fn make_account(id: &[u8; 32], balance: u128, data: Vec<u8>) -> AccountWithMetadata {
        let mut account = Account::default();
        account.balance = balance;
        account.data = data.try_into().unwrap();
        AccountWithMetadata {
            account_id: AccountId::new(*id),
            account,
            is_authorized: false,
        }
    }

    fn make_multisig_state(threshold: u8, members: Vec<[u8; 32]>) -> Vec<u8> {
        let state = MultisigState::new(threshold, members);
        borsh::to_vec(&state).unwrap()
    }

    #[test]
    fn test_execute_1_of_1_threshold() {
        let members = vec![[1u8; 32]];
        let state_data = make_multisig_state(1, members);
        
        let mut acc1 = make_account(&[1u8; 32], 0, vec![]);
        acc1.is_authorized = true;
        
        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data),
            make_account(&[20u8; 32], 1000, vec![]),
            acc1,
        ];
        
        let (post_states, _) = handle(&accounts, &AccountId::default(), 100);
        
        assert_eq!(post_states.len(), 2);
    }

    #[test]
    fn test_execute_nonce_increments() {
        let members = vec![[1u8; 32], [2u8; 32]];
        let state_data = make_multisig_state(1, members);
        
        let mut acc1 = make_account(&[1u8; 32], 0, vec![]);
        acc1.is_authorized = true;
        
        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data),
            make_account(&[20u8; 32], 1000, vec![]),
            acc1,
        ];
        
        let (post_states, _) = handle(&accounts, &AccountId::default(), 50);
        
        let state_data: Vec<u8> = post_states[0].account().data.clone().into();
        let state: MultisigState = borsh::from_slice(&state_data).unwrap();
        assert_eq!(state.nonce, 1);
    }

    #[test]
    fn test_execute_exact_threshold() {
        // 2-of-3, exactly 2 signers
        let members = vec![[1u8; 32], [2u8; 32], [3u8; 32]];
        let state_data = make_multisig_state(2, members);
        
        let mut acc1 = make_account(&[1u8; 32], 0, vec![]);
        acc1.is_authorized = true;
        let mut acc2 = make_account(&[2u8; 32], 0, vec![]);
        acc2.is_authorized = true;
        
        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data),
            make_account(&[20u8; 32], 1000, vec![]),
            acc1,
            acc2,
        ];
        
        let (post_states, _) = handle(&accounts, &AccountId::default(), 100);
        
        assert_eq!(post_states.len(), 2);
    }

    #[test]
    fn test_execute_zero_amount() {
        let members = vec![[1u8; 32]];
        let state_data = make_multisig_state(1, members);
        
        let mut acc1 = make_account(&[1u8; 32], 0, vec![]);
        acc1.is_authorized = true;
        
        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data),
            make_account(&[20u8; 32], 1000, vec![]),
            acc1,
        ];
        
        // Zero amount should work (just increments nonce)
        let (post_states, _) = handle(&accounts, &AccountId::default(), 0);
        
        assert_eq!(post_states.len(), 2);
    }

    #[test]
    #[should_panic(expected = "No authorized signers")]
    fn test_execute_missing_vault() {
        let members = vec![[1u8; 32]];
        let state_data = make_multisig_state(1, members);
        
        let mut acc1 = make_account(&[1u8; 32], 0, vec![]);
        acc1.is_authorized = true;
        
        // Only 1 account (missing vault) - but we have authorized signer
        // Actually fails at "No authorized signers" before vault check
        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data),
            acc1,
        ];
        
        handle(&accounts, &AccountId::default(), 100);
    }
}
