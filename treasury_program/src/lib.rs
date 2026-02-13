//! Treasury program

use nssa_core::account::{AccountPostState, AccountWithMetadata};
use nssa_core::program::{ProgramInput, ProgramOutput, read_nssa_inputs, write_nssa_outputs};

pub type Instruction = u8;

pub fn process(pre_states: &[AccountWithMetadata], instruction: Instruction) -> (Vec<AccountPostState>, Vec<u8>) {
    match instruction {
        0 => create_vault(pre_states),
        _ => noop(pre_states),
    }
}

fn create_vault(pre_states: &[AccountWithMetadata]) -> (Vec<AccountPostState>, Vec<u8>) {
    let post_states: Vec<AccountPostState> = pre_states
        .iter()
        .enumerate()
        .map(|(i, pre)| {
            if i == 0 {
                // Treasury state - just return as-is for now
                AccountPostState::new(pre.account.clone())
            } else {
                // Claim other accounts
                AccountPostState::new_claimed(pre.account.clone())
            }
        })
        .collect();
    (post_states, vec![])
}

fn noop(pre_states: &[AccountWithMetadata]) -> (Vec<AccountPostState>, Vec<u8>) {
    let post_states: Vec<AccountPostState> = pre_states
        .iter()
        .map(|pre| AccountPostState::new(pre.account.clone()))
        .collect();
    (post_states, vec![])
}
