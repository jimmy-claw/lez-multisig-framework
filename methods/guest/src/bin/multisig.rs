#![no_main]

use nssa_framework::prelude::*;

risc0_zkvm::guest::entry!(main);

#[nssa_program(instruction = "multisig_core::Instruction")]
mod multisig_program {
    #[allow(unused_imports)]
    use super::*;
    use ::multisig_program as handlers;
    use nssa_core::account::AccountWithMetadata;

    /// Create a new multisig with M-of-N threshold.
    #[instruction]
    pub fn create_multisig(
        #[account(init, pda = arg("create_key"))]
        multisig_state: AccountWithMetadata,
        #[account()]
        member_accounts: Vec<AccountWithMetadata>,
        create_key: [u8; 32],
        threshold: u8,
        members: Vec<[u8; 32]>,
    ) -> NssaResult {
        let mut accounts = vec![multisig_state];
        accounts.extend(member_accounts);
        let (post_states, chained_calls) =
            handlers::create_multisig::handle(&accounts, &create_key, threshold, &members);
        Ok(NssaOutput::with_chained_calls(post_states, chained_calls))
    }

    /// Create a new proposal (any member can propose).
    #[instruction]
    pub fn propose(
        #[account(mut)]
        multisig_state: AccountWithMetadata,
        #[account(signer)]
        proposer: AccountWithMetadata,
        #[account(init)]
        proposal: AccountWithMetadata,
        target_program_id: nssa_core::program::ProgramId,
        target_instruction_data: nssa_core::program::InstructionData,
        target_account_count: u8,
        pda_seeds: Vec<[u8; 32]>,
        authorized_indices: Vec<u8>,
    ) -> NssaResult {
        let accounts = vec![multisig_state, proposer, proposal];
        let (post_states, chained_calls) = handlers::propose::handle(
            &accounts,
            &target_program_id,
            &target_instruction_data,
            target_account_count,
            &pda_seeds,
            &authorized_indices,
        );
        Ok(NssaOutput::with_chained_calls(post_states, chained_calls))
    }

    /// Approve an existing proposal.
    #[instruction]
    pub fn approve(
        #[account(mut)]
        multisig_state: AccountWithMetadata,
        #[account(signer)]
        approver: AccountWithMetadata,
        #[account(mut)]
        proposal: AccountWithMetadata,
        proposal_index: u64,
    ) -> NssaResult {
        let accounts = vec![multisig_state, approver, proposal];
        let (post_states, chained_calls) = handlers::approve::handle(&accounts, proposal_index);
        Ok(NssaOutput::with_chained_calls(post_states, chained_calls))
    }

    /// Reject a proposal.
    #[instruction]
    pub fn reject(
        #[account(mut)]
        multisig_state: AccountWithMetadata,
        #[account(signer)]
        rejector: AccountWithMetadata,
        #[account(mut)]
        proposal: AccountWithMetadata,
        proposal_index: u64,
    ) -> NssaResult {
        let accounts = vec![multisig_state, rejector, proposal];
        let (post_states, chained_calls) = handlers::reject::handle(&accounts, proposal_index);
        Ok(NssaOutput::with_chained_calls(post_states, chained_calls))
    }

    /// Execute a fully-approved proposal via ChainedCall.
    #[instruction]
    pub fn execute(
        #[account(mut)]
        multisig_state: AccountWithMetadata,
        #[account(signer)]
        executor: AccountWithMetadata,
        #[account(mut)]
        proposal: AccountWithMetadata,
        #[account()]
        target_accounts: Vec<AccountWithMetadata>,
        proposal_index: u64,
    ) -> NssaResult {
        let mut accounts = vec![multisig_state, executor, proposal];
        accounts.extend(target_accounts);
        let (post_states, chained_calls) = handlers::execute::handle(&accounts, proposal_index);
        Ok(NssaOutput::with_chained_calls(post_states, chained_calls))
    }
}
