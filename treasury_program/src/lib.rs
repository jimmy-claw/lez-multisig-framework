//! Treasury program — on-chain logic for PDA demonstration with Token integration.

pub mod create_vault;
pub mod send;
pub mod deposit;

pub use treasury_core::{Instruction, get_variant, VARIANT_CREATE_VAULT, VARIANT_SEND, VARIANT_DEPOSIT};

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::ProgramOutput;

/// Dispatch incoming instructions to their handlers.
pub fn process(
    accounts: &mut [AccountWithMetadata],
    instruction: &Instruction,
) -> ProgramOutput {
    match get_variant(*instruction) {
        VARIANT_CREATE_VAULT => create_vault::handle(accounts, *instruction),
        VARIANT_SEND => send::handle(accounts, *instruction),
        VARIANT_DEPOSIT => deposit::handle(accounts, *instruction),
        _ => ProgramOutput {
            instruction_data: vec![],
            pre_states: accounts.to_vec(),
            post_states: vec![],
            chained_calls: vec![],
        }
    }
}
