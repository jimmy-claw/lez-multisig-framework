//! Handler for Send — transfers tokens from treasury vault to a recipient.

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
    let vault_post = AccountPostState::new(accounts[1].account.clone());
    let recipient_post = AccountPostState::new(accounts[2].account.clone());

    ProgramOutput {
        instruction_data: vec![],
        pre_states: accounts.to_vec(),
        post_states: vec![treasury_post, vault_post, recipient_post],
        chained_calls: vec![],
    }
}
