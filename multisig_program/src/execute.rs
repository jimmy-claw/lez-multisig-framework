// Execute handler — executes a fully-approved proposal by emitting a ChainedCall.
//
// The multisig doesn't execute actions directly. It builds a ChainedCall
// to the target program specified in the proposal, delegating actual execution.
//
// Expected accounts:
// - accounts[0]: multisig_state PDA (read threshold/membership)
// - accounts[1]: executor (must be authorized signer, must be member)
// - accounts[2]: proposal PDA account (owned by multisig program)
// - accounts[3..]: target accounts to pass to the ChainedCall

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, PdaSeed};
use multisig_core::{MultisigState, Proposal, ProposalStatus};

pub fn handle(
    accounts: &[AccountWithMetadata],
    _proposal_index: u64,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 3, "Execute requires at least multisig_state + executor + proposal");

    let multisig_account = &accounts[0];
    let executor_account = &accounts[1];
    let proposal_account = &accounts[2];
    let target_accounts = &accounts[3..];

    assert!(executor_account.is_authorized, "Executor must sign the transaction");

    // Read multisig state
    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");

    let executor_id = *executor_account.account_id.value();
    assert!(state.is_member(&executor_id), "Executor is not a multisig member");

    // Read proposal
    let proposal_data: Vec<u8> = proposal_account.account.data.clone().into();
    let mut proposal: Proposal = borsh::from_slice(&proposal_data)
        .expect("Failed to deserialize proposal");

    assert_eq!(proposal.multisig_create_key, state.create_key, "Proposal does not belong to this multisig");
    assert_eq!(proposal.status, ProposalStatus::Active, "Proposal is not active");
    assert!(
        proposal.has_threshold(state.threshold),
        "Proposal does not have enough approvals: need {}, have {}",
        state.threshold,
        proposal.approved.len()
    );

    assert_eq!(
        target_accounts.len(),
        proposal.target_account_count as usize,
        "Expected {} target accounts, got {}",
        proposal.target_account_count,
        target_accounts.len()
    );

    // Extract ChainedCall parameters from proposal
    let target_program_id = proposal.target_program_id.clone();
    let target_instruction_data = proposal.target_instruction_data.clone();
    let pda_seeds: Vec<PdaSeed> = proposal.pda_seeds.iter().map(|s| PdaSeed::new(*s)).collect();
    let authorized_indices = proposal.authorized_indices.clone();

    // Mark as executed
    proposal.status = ProposalStatus::Executed;

    // Write back proposal
    let proposal_bytes = borsh::to_vec(&proposal).unwrap();
    let mut proposal_post = proposal_account.account.clone();
    proposal_post.data = proposal_bytes.try_into().unwrap();

    // Build target account pre_states with authorization based on proposal
    let chained_pre_states: Vec<AccountWithMetadata> = target_accounts
        .iter()
        .enumerate()
        .map(|(i, acc)| {
            let mut acc = acc.clone();
            if authorized_indices.contains(&(i as u8)) {
                acc.is_authorized = true;
            }
            acc
        })
        .collect();

    let chained_call = ChainedCall {
        program_id: target_program_id,
        instruction_data: target_instruction_data,
        pre_states: chained_pre_states,
        pda_seeds,
    };

    // Multisig state unchanged
    let multisig_post = multisig_account.account.clone();
    let executor_post = executor_account.account.clone();

    // Post states for: multisig, executor, proposal, then all target accounts passed through
    let mut post_states = vec![
        AccountPostState::new(multisig_post),
        AccountPostState::new(executor_post),
        AccountPostState::new(proposal_post),
    ];

    // Target accounts must also have post_states (unchanged, they'll be modified by ChainedCall)
    for target in target_accounts {
        post_states.push(AccountPostState::new(target.account.clone()));
    }

    (post_states, vec![chained_call])
}
