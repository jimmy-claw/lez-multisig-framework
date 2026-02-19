pub mod create_multisig;
pub mod propose;
pub mod approve;
pub mod reject;
pub mod execute;

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};
use multisig_core::Instruction;

/// Main entry point called from the guest binary.
pub fn process(
    accounts: &[AccountWithMetadata],
    instruction: &Instruction,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    match instruction {
        Instruction::CreateMultisig {
            create_key,
            threshold,
            members,
        } => create_multisig::handle(accounts, create_key, *threshold, members),

        Instruction::Propose {
            target_program_id,
            target_instruction_data,
            target_account_count,
            pda_seeds,
        } => propose::handle(
            accounts,
            target_program_id,
            target_instruction_data,
            *target_account_count,
            pda_seeds,
        ),

        Instruction::Approve { proposal_index } => {
            approve::handle(accounts, *proposal_index)
        }

        Instruction::Reject { proposal_index } => {
            reject::handle(accounts, *proposal_index)
        }

        Instruction::Execute { proposal_index } => {
            execute::handle(accounts, *proposal_index)
        }
    }
}
