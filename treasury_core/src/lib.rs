// treasury_core — shared types and PDA helpers for the Treasury program.

use nssa_core::account::AccountId;
use nssa_core::program::{PdaSeed, ProgramId};

// Treasury instruction - simplest possible: just a u8 variant
// 0 = CreateVault, 1 = Send, 2 = Deposit
pub type Instruction = u8;

// Account state
pub const VAULT_SEED: &[u8] = b"vault";

pub fn compute_treasury_pda(program_id: &ProgramId) -> AccountId {
    AccountId::from((program_id, &PdaSeed::new(*b"treasury\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0")))
}
