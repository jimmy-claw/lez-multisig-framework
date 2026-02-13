// treasury_core — shared types and PDA derivation helpers for the Treasury program.

use borsh::{BorshDeserialize, BorshSerialize};
use nssa_core::account::AccountId;
use nssa_core::program::{PdaSeed, ProgramId};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

/// Instructions that the Treasury program understands.
/// 
/// This treasury demonstrates PDA patterns with Token program integration.
/// It creates token vaults and can send tokens from them.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Instruction {
    /// Create a new vault for a token.
    ///
    /// Chains to Token::NewFungibleDefinition to create a new token definition
    /// and mint the initial supply into the treasury's PDA vault.
    CreateVault {
        /// Name of the token (up to 6 bytes)
        token_name: String,
        /// Initial supply to mint
        initial_supply: u128,
    },

    /// Send tokens from the treasury vault to a recipient.
    Send {
        /// Amount to send
        amount: u128,
    },

    /// Deposit tokens into the treasury vault from an external sender.
    Deposit {
        /// Amount to deposit
        amount: u128,
    },
}

// ---------------------------------------------------------------------------
// Vault state (persisted in the treasury_state PDA)
// ---------------------------------------------------------------------------

/// State stored in the treasury_state PDA.
#[derive(Debug, Clone, Default, BorshSerialize, BorshDeserialize, Serialize, Deserialize)]
pub struct TreasuryState {
    /// How many vaults have been created.
    pub vault_count: u64,
}

// ---------------------------------------------------------------------------
// PDA derivation helpers
// ---------------------------------------------------------------------------

/// Fixed 32-byte seed for treasury state PDA.
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

/// Compute the treasury state PDA account ID.
pub fn compute_treasury_state_pda(treasury_program_id: &ProgramId) -> AccountId {
    AccountId::from((treasury_program_id, &treasury_state_pda_seed()))
}

/// Compute the vault holding PDA for a given token definition.
pub fn compute_vault_holding_pda(
    treasury_program_id: &ProgramId,
    token_definition_id: &AccountId,
) -> AccountId {
    AccountId::from((treasury_program_id, &vault_holding_pda_seed(token_definition_id)))
}

/// Build the PdaSeed for treasury state.
pub fn treasury_state_pda_seed() -> PdaSeed {
    PdaSeed::new(TREASURY_STATE_SEED)
}

/// Build the PdaSeed for a vault holding PDA.
pub fn vault_holding_pda_seed(token_definition_id: &AccountId) -> PdaSeed {
    PdaSeed::new(*token_definition_id.value())
}
