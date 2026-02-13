// treasury_core — shared types and PDA derivation helpers for the Treasury program.

use borsh::{BorshDeserialize, BorshSerialize};
use nssa_core::account::AccountId;
use nssa_core::program::{PdaSeed, ProgramId};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

/// Simple instruction encoding for the treasury program.
/// The Instruction is a Vec<u8> wrapper - serialization is handled by Message::try_new
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Instruction(Vec<u8>);

impl Instruction {
    pub fn create_vault(token_name: &str, initial_supply: u128, token_program_id: ProgramId) -> Self {
        let mut data = vec![0u8]; // variant 0
        data.push(token_name.len() as u8);
        data.extend_from_slice(token_name.as_bytes());
        data.extend_from_slice(&initial_supply.to_le_bytes());
        // ProgramId is [u32; 8]
        for &word in &token_program_id {
            data.extend_from_slice(&word.to_le_bytes());
        }
        Instruction(data)
    }

    pub fn send(amount: u128, token_program_id: ProgramId) -> Self {
        let mut data = vec![1u8]; // variant 1
        data.extend_from_slice(&amount.to_le_bytes());
        for &word in &token_program_id {
            data.extend_from_slice(&word.to_le_bytes());
        }
        Instruction(data)
    }

    pub fn deposit(amount: u128, token_program_id: ProgramId) -> Self {
        let mut data = vec![2u8]; // variant 2
        data.extend_from_slice(&amount.to_le_bytes());
        for &word in &token_program_id {
            data.extend_from_slice(&word.to_le_bytes());
        }
        Instruction(data)
    }

    pub fn variant(&self) -> u8 {
        self.0[0]
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

// ---------------------------------------------------------------------------
// Vault state
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

pub fn compute_treasury_state_pda(treasury_program_id: &ProgramId) -> AccountId {
    AccountId::from((treasury_program_id, &treasury_state_pda_seed()))
}

pub fn compute_vault_holding_pda(
    treasury_program_id: &ProgramId,
    token_definition_id: &AccountId,
) -> AccountId {
    AccountId::from((treasury_program_id, &vault_holding_pda_seed(token_definition_id)))
}

pub fn treasury_state_pda_seed() -> PdaSeed {
    PdaSeed::new(TREASURY_STATE_SEED)
}

pub fn vault_holding_pda_seed(token_definition_id: &AccountId) -> PdaSeed {
    PdaSeed::new(*token_definition_id.value())
}
