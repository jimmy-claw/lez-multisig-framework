//! Handler for Deposit — receives tokens from external sender into treasury vault.

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ProgramOutput};

pub fn handle(accounts: &mut [AccountWithMetadata], instruction: u128) -> ProgramOutput {
    if accounts.len() != 3 {
        return ProgramOutput {
            instruction_data: vec![],
            pre_states: accounts.to_vec(),
            post_states: vec![],
            chained_calls: vec![],
        };
    }

    let treasury_post = AccountPostState::new(accounts[0].account.clone());
    let sender_post = AccountPostState::new(accounts[1].account.clone());
    let vault_post = AccountPostState::new(accounts[2].account.clone());

    ProgramOutput {
        instruction_data: vec![],
        pre_states: accounts.to_vec(),
        post_states: vec![treasury_post, sender_post, vault_post],
        chained_calls: vec![],
    }
}
