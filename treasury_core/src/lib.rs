// treasury_core — shared types and PDA derivation helpers for the Treasury program.

use borsh::{BorshDeserialize, BorshSerialize};
use nssa_core::account::AccountId;
use nssa_core::program::{PdaSeed, ProgramId};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

/// Instructions for the M-of-N multisig treasury program
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Instruction {
    /// Legacy: Create a vault with authorized accounts (1-of-N)
    CreateVault {
        token_name: [u8; 6],
        initial_supply: u128,
        token_program_id: ProgramId,
        authorized_accounts: Vec<[u8; 32]>,
    },
    /// Legacy: Send from vault (1-of-N)
    Send {
        amount: u128,
        token_program_id: ProgramId,
    },
    /// Legacy: Deposit into vault
    Deposit {
        amount: u128,
    },
    
    // New M-of-N multisig instructions
    /// Create a new multisig with M-of-N threshold
    CreateMultisig {
        /// Required signatures for execution
        threshold: u8,
        /// List of member public keys (32 bytes each)
        members: Vec<[u8; 32]>,
    },
    /// Execute a transaction from the multisig vault
    Execute {
        /// Recipient account ID (for transfers)
        recipient: AccountId,
        /// Amount to transfer
        amount: u128,
    },
    /// Add a new member (requires threshold signatures)
    AddMember {
        /// New member's public key
        new_member: [u8; 32],
    },
    /// Remove a member (requires threshold signatures)
    RemoveMember {
        /// Member to remove
        member_to_remove: [u8; 32],
    },
    /// Change the threshold (requires threshold signatures)
    ChangeThreshold {
        /// New threshold value
        new_threshold: u8,
    },
}

// ---------------------------------------------------------------------------
// Multisig state (persisted in the treasury state PDA)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, BorshSerialize, BorshDeserialize)]
pub struct MultisigState {
    /// Current threshold (M)
    pub threshold: u8,
    /// Number of members (N)
    pub member_count: u8,
    /// List of member public keys
    pub members: Vec<[u8; 32]>,
    /// Nonce for replay protection
    pub nonce: u64,
}

impl MultisigState {
    /// Create a new multisig state
    pub fn new(threshold: u8, members: Vec<[u8; 32]>) -> Self {
        let member_count = members.len() as u8;
        Self {
            threshold,
            member_count,
            members,
            nonce: 0,
        }
    }

    /// Check if a public key is a member
    pub fn is_member(&self, pk: &[u8; 32]) -> bool {
        self.members.contains(pk)
    }

    /// Count how many of the given signers are members
    pub fn count_valid_signers(&self, signers: &[[u8; 32]]) -> usize {
        signers
            .iter()
            .filter(|s| self.is_member(s))
            .count()
    }
}

// ---------------------------------------------------------------------------
// Legacy TreasuryState (for backwards compatibility with 1-of-N)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, BorshSerialize, BorshDeserialize)]
pub struct TreasuryState {
    pub vault_count: u64,
    pub authorized_accounts: Vec<[u8; 32]>,
}

// ---------------------------------------------------------------------------
// PDA derivation helpers
// ---------------------------------------------------------------------------

const MULTISIG_STATE_SEED: [u8; 32] = {
    let mut seed = [0u8; 32];
    let tag = b"multisig_state";
    let mut i = 0;
    while i < tag.len() {
        seed[i] = tag[i];
        i += 1;
    }
    seed
};

pub fn multisig_state_pda_seed() -> PdaSeed {
    PdaSeed::new(MULTISIG_STATE_SEED)
}

pub fn compute_multisig_state_pda(program_id: &ProgramId) -> AccountId {
    AccountId::from((program_id, &multisig_state_pda_seed()))
}

/// Compute vault PDA seed (same as before for backwards compatibility)
pub fn vault_pda_seed() -> PdaSeed {
    let seed = [0u8; 32];
    PdaSeed::new(seed)
}

pub fn compute_vault_pda(program_id: &ProgramId) -> AccountId {
    AccountId::from((program_id, &vault_pda_seed()))
}

// Legacy helpers
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
