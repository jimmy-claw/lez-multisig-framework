// multisig_core — shared types and PDA derivation helpers for the Multisig program.
//
// A multisig is a governance wrapper: it collects M-of-N approvals and then
// executes a ChainedCall to a target program. The multisig itself never
// directly modifies external accounts — it only stores proposals and voting
// state, then delegates execution via NSSA ChainedCalls.
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
/// 1. Any member calls `Propose` with target program details — creates on-chain proposal
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
    /// The proposal stores what ChainedCall to make when executed.
    Propose {
        /// Target program to call when executed
        target_program_id: ProgramId,
        /// Serialized instruction data for the target program
        target_instruction_data: InstructionData,
        /// Number of target accounts that will be passed at execute time.
        /// (Account IDs are not stored — they're passed as tx accounts at execute time.)
        target_account_count: u8,
        /// PDA seeds for authorization in the chained call
        pda_seeds: Vec<PdaSeed>,
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
    /// The transaction must include the target accounts after [multisig_state, executor].
    Execute {
        proposal_index: u64,
    },
}

// ---------------------------------------------------------------------------
// Proposal state (stored on-chain in MultisigState)
// ---------------------------------------------------------------------------

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

/// A proposal stored on-chain. Contains the ChainedCall parameters
/// so that Execute can reconstruct the call.
#[derive(Debug, Clone, BorshSerialize, BorshDeserialize)]
pub struct Proposal {
    /// Unique index
    pub index: u64,
    /// Who proposed it
    pub proposer: [u8; 32],

    // -- ChainedCall parameters --
    /// Target program to call
    pub target_program_id: ProgramId,
    /// Serialized instruction data for target program
    pub target_instruction_data: InstructionData,
    /// Expected number of target accounts at execute time
    pub target_account_count: u8,
    /// PDA seeds for the chained call
    pub pda_seeds: Vec<PdaSeed>,

    // -- Voting state --
    /// Account IDs that have approved (proposer auto-approves)
    pub approved: Vec<[u8; 32]>,
    /// Account IDs that have rejected
    pub rejected: Vec<[u8; 32]>,
    /// Current status
    pub status: ProposalStatus,
}

impl Proposal {
    pub fn new(
        index: u64,
        proposer: [u8; 32],
        target_program_id: ProgramId,
        target_instruction_data: InstructionData,
        target_account_count: u8,
        pda_seeds: Vec<PdaSeed>,
    ) -> Self {
        Self {
            index,
            proposer,
            target_program_id,
            target_instruction_data,
            target_account_count,
            pda_seeds,
            approved: vec![proposer], // proposer auto-approves
            rejected: vec![],
            status: ProposalStatus::Active,
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
    /// Transaction/proposal counter
    pub transaction_index: u64,
    /// Active and recent proposals
    pub proposals: Vec<Proposal>,
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
            proposals: vec![],
        }
    }

    pub fn is_member(&self, id: &[u8; 32]) -> bool {
        self.members.contains(id)
    }

    pub fn get_proposal_mut(&mut self, index: u64) -> Option<&mut Proposal> {
        self.proposals.iter_mut().find(|p| p.index == index)
    }

    pub fn get_proposal(&self, index: u64) -> Option<&Proposal> {
        self.proposals.iter().find(|p| p.index == index)
    }

    /// Create a new proposal, returns the proposal index
    pub fn create_proposal(
        &mut self,
        proposer: [u8; 32],
        target_program_id: ProgramId,
        target_instruction_data: InstructionData,
        target_account_count: u8,
        pda_seeds: Vec<PdaSeed>,
    ) -> u64 {
        self.transaction_index += 1;
        let index = self.transaction_index;
        let proposal = Proposal::new(
            index,
            proposer,
            target_program_id,
            target_instruction_data,
            target_account_count,
            pda_seeds,
        );
        self.proposals.push(proposal);
        index
    }

    /// Clean up non-active proposals
    pub fn cleanup_proposals(&mut self) {
        self.proposals.retain(|p| p.status == ProposalStatus::Active);
    }
}

// ---------------------------------------------------------------------------
// PDA derivation helpers
// ---------------------------------------------------------------------------

/// Compute PDA seed for a multisig identified by `create_key`.
pub fn multisig_state_pda_seed(create_key: &[u8; 32]) -> PdaSeed {
    let tag = b"multisig_state";
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
