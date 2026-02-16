pub mod create_vault;
pub mod deposit;
pub mod send;
pub mod create_multisig;
pub mod execute;
pub mod add_member;
pub mod remove_member;
pub mod change_threshold;

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};
use treasury_core::Instruction;

/// Main entry point called from the guest binary.
pub fn process(
    accounts: &[AccountWithMetadata],
    instruction: &Instruction,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    match instruction {
        // Legacy instructions (for backwards compatibility)
        Instruction::CreateVault {
            token_name,
            initial_supply,
            token_program_id,
            authorized_accounts,
        } => create_vault::handle(accounts, token_name, *initial_supply, token_program_id, authorized_accounts),
        
        Instruction::Send { amount, token_program_id } => {
            send::handle(accounts, *amount, token_program_id)
        }
        
        Instruction::Deposit { amount } => {
            deposit::handle(accounts, *amount)
        }
        
        // New M-of-N multisig instructions
        Instruction::CreateMultisig {
            threshold,
            members,
        } => create_multisig::handle(accounts, *threshold, members),
        
        Instruction::Execute { recipient, amount } => {
            execute::handle(accounts, recipient, *amount)
        }
        
        Instruction::AddMember { new_member } => {
            add_member::handle(accounts, new_member)
        }
        
        Instruction::RemoveMember { member_to_remove } => {
            remove_member::handle(accounts, member_to_remove)
        }
        
        Instruction::ChangeThreshold { new_threshold } => {
            change_threshold::handle(accounts, *new_threshold)
        }
    }
}
