// treasury_core — shared types and PDA derivation helpers for the Treasury program.

use borsh::{BorshDeserialize, BorshSerialize};
use nssa_core::account::AccountId;
use nssa_core::program::{PdaSeed, ProgramId};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Instruction {
    CreateVault {
        token_name: [u8; 6],
        initial_supply: u128,
        token_program_id: ProgramId,
    },
    Send {
        amount: u128,
        token_program_id: ProgramId,
    },
    Deposit {
        amount: u128,
        token_program_id: ProgramId,
    },
}

// ---------------------------------------------------------------------------
// Vault state (persisted in the treasury_state PDA)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, BorshSerialize, BorshDeserialize)]
pub struct TreasuryState {
    pub vault_count: u64,
}

// ---------------------------------------------------------------------------
// PDA derivation helpers
// ---------------------------------------------------------------------------

const TREASURY_STATE_SEED: [u8; 32] = {
    let mut seed = [0u8; 32];
    let tag = b"treasury_state";
    let mut i = 0;
    while i < tag.len() {
        seed[i] = tag[i];
        i += 1;
    }
    seed
};

pub fn treasury_state_pda_seed() -> PdaSeed {
    PdaSeed::new(TREASURY_STATE_SEED)
}

pub fn vault_holding_pda_seed(token_definition_id: &AccountId) -> PdaSeed {
    PdaSeed::new(*token_definition_id.value())
}

pub fn compute_treasury_state_pda(program_id: &ProgramId) -> AccountId {
    AccountId::from((program_id, &treasury_state_pda_seed()))
}

pub fn compute_vault_holding_pda(
    program_id: &ProgramId,
    token_definition_id: &AccountId,
) -> AccountId {
    AccountId::from((program_id, &vault_holding_pda_seed(token_definition_id)))
}
