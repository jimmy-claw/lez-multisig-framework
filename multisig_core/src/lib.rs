// multisig_core — shared types and PDA derivation helpers for the Multisig program.
//
// A multisig is a governance wrapper: it collects M-of-N approvals and then
// executes a ChainedCall to a target program. The multisig itself never
// directly modifies external accounts — it only stores proposals and voting
// state, then delegates execution via LEZ ChainedCalls.
//
// Proposals are stored as separate PDA accounts (Squads-style), not inside
// MultisigState. This prevents state bloat and allows independent lifecycle.
//
// Inspired by Squads Protocol v4 (Solana).

use borsh::{BorshDeserialize, BorshSerialize};
use nssa_core::account::AccountId;
use nssa_core::program::{InstructionData, PdaSeed, ProgramId};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

/// Instructions for the M-of-N multisig program.
///
/// Flow:
/// 1. Any member calls `Propose` — creates a new proposal PDA account
/// 2. Other members call `Approve { proposal_index }` — adds their approval
/// 3. Once M approvals collected, anyone calls `Execute { proposal_index }`
///    → multisig emits a ChainedCall to the target program
/// 4. Members can also `Reject` proposals
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Instruction {
    /// Create a new multisig with M-of-N threshold.
    CreateMultisig {
        /// Unique key for PDA derivation — allows multiple multisigs per program
        create_key: [u8; 32],
        /// Required signatures for execution (M)
        threshold: u8,
        /// List of member account IDs (32 bytes each, derived from public keys)
        members: Vec<[u8; 32]>,
    },

    /// Create a new proposal (any member can propose).
    /// Creates a separate PDA account for the proposal.
    Propose {
        /// Target program to call when executed
        target_program_id: ProgramId,
        /// Serialized instruction data for the target program
        target_instruction_data: InstructionData,
        /// Number of target accounts that will be passed at execute time.
        target_account_count: u8,
        /// PDA seeds for authorization in the chained call
        pda_seeds: Vec<[u8; 32]>,
        /// Which target account indices (0-based) get `is_authorized = true`
        authorized_indices: Vec<u8>,
    },

    /// Approve an existing proposal (any member, one approval per member)
    Approve {
        proposal_index: u64,
    },

    /// Reject a proposal
    Reject {
        proposal_index: u64,
    },

    /// Execute a fully-approved proposal.
    /// The transaction must include the target accounts after [multisig_state, executor, proposal].
    Execute {
        proposal_index: u64,
    },

    /// Propose adding a new member to the multisig (requires M approvals to execute).
    ProposeAddMember {
        new_member: [u8; 32],
    },

    /// Propose removing a member from the multisig (requires M approvals to execute).
    /// Will be rejected on execute if removing would make N < M.
    ProposeRemoveMember {
        member: [u8; 32],
    },

    /// Propose changing the approval threshold (requires M approvals to execute).
    /// Must satisfy 1 ≤ new_threshold ≤ N (checked on execute).
    ProposeChangeThreshold {
        new_threshold: u8,
    },
}

// ---------------------------------------------------------------------------
// Proposal state (stored in its own PDA account)
// ---------------------------------------------------------------------------

/// Configuration change action embedded in a proposal.
/// When a proposal has a `config_action`, execute modifies MultisigState
/// directly instead of emitting a ChainedCall.
#[derive(Debug, Clone, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub enum ConfigAction {
    /// Add a new member to the multisig
    AddMember { new_member: [u8; 32] },
    /// Remove an existing member from the multisig
    RemoveMember { member: [u8; 32] },
    /// Change the approval threshold
    ChangeThreshold { new_threshold: u8 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub enum ProposalStatus {
    /// Proposal is active and accepting approvals
    Active,
    /// Proposal has reached threshold and been executed
    Executed,
    /// Proposal was rejected
    Rejected,
    /// Proposal was cancelled
    Cancelled,
}

/// A proposal stored in its own PDA account.
/// PDA derived from: proposal_pda_seed(create_key, proposal_index)
#[derive(Debug, Clone, BorshSerialize, BorshDeserialize)]
pub struct Proposal {
    /// Unique index (matches MultisigState.transaction_index at creation time)
    pub index: u64,
    /// Who proposed it
    pub proposer: [u8; 32],
    /// The create_key of the parent multisig (for verification)
    pub multisig_create_key: [u8; 32],

    // -- ChainedCall parameters --
    /// Target program to call
    pub target_program_id: ProgramId,
    /// Serialized instruction data for target program
    pub target_instruction_data: InstructionData,
    /// Expected number of target accounts at execute time
    pub target_account_count: u8,
    /// PDA seeds for the chained call (multisig proves ownership)
    pub pda_seeds: Vec<[u8; 32]>,
    /// Which target account indices (0-based) get `is_authorized = true`
    pub authorized_indices: Vec<u8>,

    // -- Voting state --
    /// Account IDs that have approved (proposer auto-approves)
    pub approved: Vec<[u8; 32]>,
    /// Account IDs that have rejected
    pub rejected: Vec<[u8; 32]>,
    /// Current status
    pub status: ProposalStatus,
    /// Optional config change action (if set, execute modifies MultisigState instead of ChainedCall)
    pub config_action: Option<ConfigAction>,
}

impl Proposal {
    pub fn new(
        index: u64,
        proposer: [u8; 32],
        multisig_create_key: [u8; 32],
        target_program_id: ProgramId,
        target_instruction_data: InstructionData,
        target_account_count: u8,
        pda_seeds: Vec<[u8; 32]>,
        authorized_indices: Vec<u8>,
    ) -> Self {
        Self {
            index,
            proposer,
            multisig_create_key,
            target_program_id,
            target_instruction_data,
            target_account_count,
            pda_seeds,
            authorized_indices,
            approved: vec![proposer],
            rejected: vec![],
            status: ProposalStatus::Active,
            config_action: None,
        }
    }

    /// Create a new config change proposal (no ChainedCall target)
    pub fn new_config(
        index: u64,
        proposer: [u8; 32],
        multisig_create_key: [u8; 32],
        action: ConfigAction,
    ) -> Self {
        Self {
            index,
            proposer,
            multisig_create_key,
            target_program_id: [0u32; 8],
            target_instruction_data: vec![],
            target_account_count: 0,
            pda_seeds: vec![],
            authorized_indices: vec![],
            approved: vec![proposer],
            rejected: vec![],
            status: ProposalStatus::Active,
            config_action: Some(action),
        }
    }

    /// Add an approval. Returns true if this was a new approval.
    pub fn approve(&mut self, member: [u8; 32]) -> bool {
        if self.approved.contains(&member) {
            return false;
        }
        self.rejected.retain(|r| r != &member);
        self.approved.push(member);
        true
    }

    /// Add a rejection. Returns true if this was a new rejection.
    pub fn reject(&mut self, member: [u8; 32]) -> bool {
        if self.rejected.contains(&member) {
            return false;
        }
        self.approved.retain(|a| a != &member);
        self.rejected.push(member);
        true
    }

    /// Check if the proposal has enough approvals
    pub fn has_threshold(&self, threshold: u8) -> bool {
        self.approved.len() >= threshold as usize
    }

    /// Check if the proposal can never reach threshold
    pub fn is_dead(&self, threshold: u8, member_count: u8) -> bool {
        let remaining = member_count as usize - self.rejected.len();
        remaining < threshold as usize
    }
}

// ---------------------------------------------------------------------------
// Multisig state (persisted in the multisig state PDA)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, BorshSerialize, BorshDeserialize)]
pub struct MultisigState {
    /// Unique key used to derive this multisig's PDA
    pub create_key: [u8; 32],
    /// Current threshold (M)
    pub threshold: u8,
    /// Number of members (N)
    pub member_count: u8,
    /// List of member account IDs
    pub members: Vec<[u8; 32]>,
    /// Transaction/proposal counter (incremented on each Propose)
    pub transaction_index: u64,
}

impl MultisigState {
    pub fn new(create_key: [u8; 32], threshold: u8, members: Vec<[u8; 32]>) -> Self {
        let member_count = members.len() as u8;
        Self {
            create_key,
            threshold,
            member_count,
            members,
            transaction_index: 0,
        }
    }

    pub fn is_member(&self, id: &[u8; 32]) -> bool {
        self.members.contains(id)
    }

    /// Increment and return the next proposal index
    pub fn next_proposal_index(&mut self) -> u64 {
        self.transaction_index += 1;
        self.transaction_index
    }
}

// ---------------------------------------------------------------------------
// PDA derivation helpers
// ---------------------------------------------------------------------------

/// Compute PDA seed for a multisig identified by `create_key`.
pub fn multisig_state_pda_seed(create_key: &[u8; 32]) -> PdaSeed {
    let tag = b"multisig_state__"; // 16 bytes, padded
    let mut seed = [0u8; 32];
    for i in 0..tag.len() {
        seed[i] = tag[i];
    }
    for i in 0..32 {
        seed[i] ^= create_key[i];
    }
    PdaSeed::new(seed)
}

/// Compute the on-chain AccountId (PDA) for a multisig.
pub fn compute_multisig_state_pda(program_id: &ProgramId, create_key: &[u8; 32]) -> AccountId {
    AccountId::from((program_id, &multisig_state_pda_seed(create_key)))
}

/// Compute PDA seed for a proposal.
/// Each proposal gets a unique PDA: seed = XOR("multisig_prop___", create_key) XOR proposal_index in last 8 bytes.
pub fn proposal_pda_seed(create_key: &[u8; 32], proposal_index: u64) -> PdaSeed {
    let tag = b"multisig_prop___"; // 16 bytes
    let mut seed = [0u8; 32];
    for i in 0..tag.len() {
        seed[i] = tag[i];
    }
    // XOR create_key
    for i in 0..32 {
        seed[i] ^= create_key[i];
    }
    // Mix in proposal_index (big-endian in last 8 bytes)
    let idx_bytes = proposal_index.to_be_bytes();
    for i in 0..8 {
        seed[24 + i] ^= idx_bytes[i];
    }
    PdaSeed::new(seed)
}

/// Compute the on-chain AccountId (PDA) for a proposal.
pub fn compute_proposal_pda(program_id: &ProgramId, create_key: &[u8; 32], proposal_index: u64) -> AccountId {
    AccountId::from((program_id, &proposal_pda_seed(create_key, proposal_index)))
}

/// Compute PDA seed for a multisig vault (holds assets authorized by the multisig).
/// Uses "multisig_vault_" tag XORed with create_key — different from state PDA.
pub fn vault_pda_seed(create_key: &[u8; 32]) -> PdaSeed {
    let tag = b"multisig_vault__"; // 16 bytes, padded
    let mut seed = [0u8; 32];
    for i in 0..tag.len() {
        seed[i] = tag[i];
    }
    for i in 0..32 {
        seed[i] ^= create_key[i];
    }
    PdaSeed::new(seed)
}

/// Compute the on-chain AccountId (PDA) for a multisig's vault.
pub fn compute_vault_pda(program_id: &ProgramId, create_key: &[u8; 32]) -> AccountId {
    AccountId::from((program_id, &vault_pda_seed(create_key)))
}

/// Get the raw [u8; 32] seed bytes for a vault PDA (for storage in proposals).
pub fn vault_pda_seed_bytes(create_key: &[u8; 32]) -> [u8; 32] {
    let tag = b"multisig_vault__"; // 16 bytes, padded
    let mut seed = [0u8; 32];
    for i in 0..tag.len() {
        seed[i] = tag[i];
    }
    for i in 0..32 {
        seed[i] ^= create_key[i];
    }
    seed
}
