// Propose handler — creates a new proposal storing ChainedCall parameters.
//
// Expected accounts:
// - accounts[0]: multisig_state (PDA)
// - accounts[1]: proposer (must be authorized signer, must be member)

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, InstructionData, PdaSeed, ProgramId};
use multisig_core::MultisigState;

pub fn handle(
    accounts: &[AccountWithMetadata],
    target_program_id: &ProgramId,
    target_instruction_data: &InstructionData,
    target_account_count: u8,
    pda_seeds: &[PdaSeed],
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 2, "Propose requires multisig_state + proposer accounts");

    let multisig_account = &accounts[0];
    let proposer_account = &accounts[1];

    assert!(proposer_account.is_authorized, "Proposer must sign the transaction");

    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let mut state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");

    let proposer_id = *proposer_account.account_id.value();
    assert!(state.is_member(&proposer_id), "Proposer is not a multisig member");

    // Create the proposal with ChainedCall parameters
    let _index = state.create_proposal(
        proposer_id,
        target_program_id.clone(),
        target_instruction_data.clone(),
        target_account_count,
        pda_seeds.to_vec(),
    );

    // Serialize updated state
    let state_bytes = borsh::to_vec(&state).unwrap();
    let mut multisig_post = multisig_account.account.clone();
    multisig_post.data = state_bytes.try_into().unwrap();

    let proposer_post = proposer_account.account.clone();

    (vec![AccountPostState::new(multisig_post), AccountPostState::new(proposer_post)], vec![])
}
