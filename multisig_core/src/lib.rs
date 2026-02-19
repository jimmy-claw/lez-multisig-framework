// multisig_core — shared types and PDA derivation helpers for the Multisig program.
//
// Inspired by Squads Protocol v4 (Solana) — proposals are stored on-chain,
// any member can propose/approve/execute independently.

use borsh::{BorshDeserialize, BorshSerialize};
use nssa_core::account::AccountId;
use nssa_core::program::{PdaSeed, ProgramId};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

/// Instructions for the M-of-N multisig program.
///
/// Flow (Squads-style):
/// 1. Any member calls `Propose` with an action — creates on-chain proposal
/// 2. Other members call `Approve { proposal_index }` — adds their approval
/// 3. Once M approvals collected, anyone calls `Execute { proposal_index }`
/// 4. Members can also `Reject` proposals
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Instruction {
    /// Create a new multisig with M-of-N threshold.
    /// `create_key` is a unique 32-byte value (e.g. random) that deterministically
    /// derives the multisig's PDA. Inspired by Squads Protocol v4.
    CreateMultisig {
        /// Unique key for PDA derivation — allows multiple multisigs per program
        create_key: [u8; 32],
        /// Required signatures for execution (M)
        threshold: u8,
        /// List of member account IDs (32 bytes each, derived from public keys)
        members: Vec<[u8; 32]>,
    },

    /// Create a new proposal (any member can propose)
    Propose {
        /// The action to execute once approved
        action: ProposalAction,
    },

    /// Approve an existing proposal (any member, one approval per member)
    Approve {
        /// Index of the proposal to approve
        proposal_index: u64,
    },

    /// Reject a proposal
    Reject {
        /// Index of the proposal to reject
        proposal_index: u64,
    },

    /// Execute a fully-approved proposal
    Execute {
        /// Index of the proposal to execute
        proposal_index: u64,
    },
}

/// Actions that can be proposed for multisig approval.
#[derive(Debug, Clone, Serialize, Deserialize, BorshSerialize, BorshDeserialize, PartialEq)]
pub enum ProposalAction {
    /// Transfer funds from the multisig vault
    Transfer {
        recipient: AccountId,
        amount: u128,
    },
    /// Add a new member
    AddMember {
        new_member: [u8; 32],
    },
    /// Remove a member
    RemoveMember {
        member_to_remove: [u8; 32],
    },
    /// Change the threshold
    ChangeThreshold {
        new_threshold: u8,
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
    /// Proposal was rejected (N - M + 1 rejections = can never reach threshold)
    Rejected,
    /// Proposal was cancelled
    Cancelled,
}

#[derive(Debug, Clone, BorshSerialize, BorshDeserialize)]
pub struct Proposal {
    /// Unique index
    pub index: u64,
    /// The proposed action
    pub action: ProposalAction,
    /// Who proposed it
    pub proposer: [u8; 32],
    /// Account IDs that have approved (proposer auto-approves)
    pub approved: Vec<[u8; 32]>,
    /// Account IDs that have rejected
    pub rejected: Vec<[u8; 32]>,
    /// Current status
    pub status: ProposalStatus,
}

impl Proposal {
    pub fn new(index: u64, action: ProposalAction, proposer: [u8; 32]) -> Self {
        Self {
            index,
            action,
            proposer,
            approved: vec![proposer], // proposer auto-approves
            rejected: vec![],
            status: ProposalStatus::Active,
        }
    }

    /// Add an approval. Returns true if this was a new approval.
    pub fn approve(&mut self, member: [u8; 32]) -> bool {
        if self.approved.contains(&member) {
            return false; // already approved
        }
        // Remove from rejected if previously rejected
        self.rejected.retain(|r| r != &member);
        self.approved.push(member);
        true
    }

    /// Add a rejection. Returns true if this was a new rejection.
    pub fn reject(&mut self, member: [u8; 32]) -> bool {
        if self.rejected.contains(&member) {
            return false; // already rejected
        }
        // Remove from approved if previously approved
        self.approved.retain(|a| a != &member);
        self.rejected.push(member);
        true
    }

    /// Check if the proposal has enough approvals
    pub fn has_threshold(&self, threshold: u8) -> bool {
        self.approved.len() >= threshold as usize
    }

    /// Check if the proposal can never reach threshold
    /// (when rejections >= N - M + 1, i.e., not enough remaining members to approve)
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
    /// Unique key used to derive this multisig's PDA (Squads-style)
    pub create_key: [u8; 32],
    /// Current threshold (M)
    pub threshold: u8,
    /// Number of members (N)
    pub member_count: u8,
    /// List of member account IDs (derived from public keys)
    pub members: Vec<[u8; 32]>,
    /// Transaction/proposal counter
    pub transaction_index: u64,
    /// Active and recent proposals
    pub proposals: Vec<Proposal>,
}

impl MultisigState {
    /// Create a new multisig state
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

    /// Check if an account ID is a member
    pub fn is_member(&self, id: &[u8; 32]) -> bool {
        self.members.contains(id)
    }

    /// Count how many of the given signers are members
    pub fn count_valid_signers(&self, signers: &[[u8; 32]]) -> usize {
        signers
            .iter()
            .filter(|s| self.is_member(s))
            .count()
    }

    /// Get a mutable reference to a proposal by index
    pub fn get_proposal_mut(&mut self, index: u64) -> Option<&mut Proposal> {
        self.proposals.iter_mut().find(|p| p.index == index)
    }

    /// Get a proposal by index
    pub fn get_proposal(&self, index: u64) -> Option<&Proposal> {
        self.proposals.iter().find(|p| p.index == index)
    }

    /// Create a new proposal, returns the proposal index
    pub fn create_proposal(&mut self, action: ProposalAction, proposer: [u8; 32]) -> u64 {
        self.transaction_index += 1;
        let index = self.transaction_index;
        let proposal = Proposal::new(index, action, proposer);
        self.proposals.push(proposal);
        index
    }

    /// Clean up executed/rejected/cancelled proposals to save space
    pub fn cleanup_proposals(&mut self) {
        self.proposals.retain(|p| p.status == ProposalStatus::Active);
    }

    /// Remove all proposals regardless of status (e.g. after execution)
    pub fn clear_all_proposals(&mut self) {
        self.proposals.clear();
    }
}

// ---------------------------------------------------------------------------
// PDA derivation helpers
// ---------------------------------------------------------------------------

/// Compute PDA seed for a multisig identified by `create_key`.
/// Seed = XOR("multisig_state\0..." padded to 32 bytes, create_key).
/// Uniqueness comes from create_key; the tag prevents collisions with other programs.
/// The outer NSSA PDA derivation (SHA256 of prefix + program_id + seed) ensures
/// the final AccountId is cryptographically unique.
pub fn multisig_state_pda_seed(create_key: &[u8; 32]) -> PdaSeed {
    let tag = b"multisig_state";
    let mut seed = [0u8; 32];
    // XOR tag into seed, then XOR create_key
    for i in 0..tag.len() {
        seed[i] = tag[i];
    }
    for i in 0..32 {
        seed[i] ^= create_key[i];
    }
    PdaSeed::new(seed)
}

/// Compute the on-chain AccountId (PDA) for a multisig given program_id and create_key.
pub fn compute_multisig_state_pda(program_id: &ProgramId, create_key: &[u8; 32]) -> AccountId {
    AccountId::from((program_id, &multisig_state_pda_seed(create_key)))
}
