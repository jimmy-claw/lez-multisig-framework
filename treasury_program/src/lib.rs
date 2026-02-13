//! Treasury program — on-chain logic for PDA demonstration with Token integration.

pub mod create_vault;
pub mod send;
pub mod deposit;

pub use treasury_core::Instruction;

use nssa_core::account::{Account, AccountId, AccountWithMetadata};
use nssa_core::program::{ChainedCall, InstructionData, PdaSeed, ProgramId, ProgramOutput};
use treasury_core::{compute_treasury_state_pda, compute_vault_holding_pda, TreasuryState};

/// Dispatch incoming instructions to their handlers.
pub fn process(
    program_id: &ProgramId,
    accounts: &mut [AccountWithMetadata],
    instruction: &Instruction,
) -> ProgramOutput {
    match instruction {
        Instruction::CreateVault {
            token_name,
            initial_supply,
        } => create_vault::handle(accounts, program_id, token_name, *initial_supply),
        Instruction::Send { amount } => send::handle(accounts, *amount),
        Instruction::Deposit { amount } => deposit::handle(accounts, *amount),
    }
}
