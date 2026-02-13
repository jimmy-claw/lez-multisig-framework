//! Treasury guest binary

use nssa_core::program::{ProgramInput, read_nssa_inputs, write_nssa_outputs};

type Instruction = u8;

fn main() {
    let (
        ProgramInput {
            pre_states,
            instruction,
        },
        instruction_words,
    ) = read_nssa_inputs::<Instruction>();

    let post_states: Vec<nssa_core::program::AccountPostState> = pre_states
        .iter()
        .enumerate()
        .map(|(i, pre)| {
            if instruction == 0 && i == 0 {
                // CreateVault: first account is treasury state
                nssa_core::program::AccountPostState::new(pre.account.clone())
            } else if instruction == 0 {
                // CreateVault: other accounts get claimed
                nssa_core::program::AccountPostState::new_claimed(pre.account.clone())
            } else {
                // Default: just pass through
                nssa_core::program::AccountPostState::new(pre.account.clone())
            }
        })
        .collect();

    write_nssa_outputs(instruction_words, pre_states, post_states);
}
