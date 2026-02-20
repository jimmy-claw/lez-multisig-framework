// Propose handler — creates a new proposal as a separate PDA account.
//
// Expected accounts:
// - accounts[0]: multisig_state PDA (read membership, increment tx_index)
// - accounts[1]: proposer (must be authorized signer, must be member)
// - accounts[2]: proposal PDA account (must be Account::default() = uninitialized)

use nssa_core::account::{Account, AccountWithMetadata};
use nssa_core::program::{AccountPostState, ChainedCall, InstructionData, ProgramId};
use multisig_core::{MultisigState, Proposal};

pub fn handle(
    accounts: &[AccountWithMetadata],
    target_program_id: &ProgramId,
    target_instruction_data: &InstructionData,
    target_account_count: u8,
    pda_seeds: &[[u8; 32]],
    authorized_indices: &[u8],
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 3, "Propose requires multisig_state + proposer + proposal accounts");

    let multisig_account = &accounts[0];
    let proposer_account = &accounts[1];
    let proposal_account = &accounts[2];

    assert!(proposer_account.is_authorized, "Proposer must sign the transaction");

    // Proposal account must be uninitialized
    assert!(
        proposal_account.account == Account::default(),
        "Proposal account must be uninitialized"
    );

    // Read and update multisig state (increment transaction_index)
    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let mut state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");

    let proposer_id = *proposer_account.account_id.value();
    assert!(state.is_member(&proposer_id), "Proposer is not a multisig member");

    let proposal_index = state.next_proposal_index();

    // Create the proposal
    let proposal = Proposal::new(
        proposal_index,
        proposer_id,
        state.create_key,
        target_program_id.clone(),
        target_instruction_data.clone(),
        target_account_count,
        pda_seeds.to_vec(),
        authorized_indices.to_vec(),
    );

    // Serialize updated multisig state (with incremented tx_index)
    let state_bytes = borsh::to_vec(&state).unwrap();
    let mut multisig_post = multisig_account.account.clone();
    multisig_post.data = state_bytes.try_into().unwrap();

    // Serialize proposal into new account and claim it
    let proposal_bytes = borsh::to_vec(&proposal).unwrap();
    let mut proposal_post = Account::default();
    proposal_post.data = proposal_bytes.try_into().unwrap();

    let proposer_post = proposer_account.account.clone();

    (
        vec![
            AccountPostState::new(multisig_post),
            AccountPostState::new(proposer_post),
            AccountPostState::new_claimed(proposal_post),
        ],
        vec![],
    )
}
