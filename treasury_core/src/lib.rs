// treasury_core — shared types and PDA derivation helpers for the Treasury program.

use borsh::{BorshDeserialize, BorshSerialize};
use nssa_core::account::AccountId;
use nssa_core::program::{PdaSeed, ProgramId};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

/// Treasury instruction encoding using simple u128:
/// - High 8 bits: variant (0=create_vault, 1=send, 2=deposit)
/// - Remaining bits: encoded data
pub type Instruction = u128;

pub const VARIANT_CREATE_VAULT: u128 = 0;
pub const VARIANT_SEND: u128 = 1;
pub const VARIANT_DEPOSIT: u128 = 2;

pub fn get_variant(instruction: Instruction) -> u128 {
    instruction >> 120 // top 8 bits
}

pub fn create_vault_instruction(token_name: &str, initial_supply: u128, token_program_id: ProgramId) -> Instruction {
    // Format: [variant: 8][name_len: 8][name: 48][supply: 128][program_id: 256] = 448 bits
    let variant = VARIANT_CREATE_VAULT << 120;
    let name_len = (token_name.len() as u128) << 112;
    // Pack name into 48 bits (6 bytes)
    let name_bytes = token_name.as_bytes();
    let mut name_packed = 0u128;
    for (i, &b) in name_bytes.iter().take(6).enumerate() {
        name_packed |= (b as u128) << (40 - i * 8);
    }
    let name_packed_bits = name_packed << 64;
    let supply_bits = initial_supply << 128;
    
    variant | name_len | name_packed_bits | supply_bits | 0 // TODO: encode program_id
}

pub fn send_instruction(amount: u128) -> Instruction {
    (VARIANT_SEND << 120) | amount
}

pub fn deposit_instruction(amount: u128) -> Instruction {
    (VARIANT_DEPOSIT << 120) | amount
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
