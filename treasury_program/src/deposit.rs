use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, ProgramId};

/// Handle the `Deposit` instruction.
///
/// Accounts: [treasury_state, sender_holding, vault_holding]
pub fn handle(
    accounts: &[AccountWithMetadata],
    amount: u128,
    token_program_id: &ProgramId,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() == 3, "Deposit requires exactly 3 accounts");

    let treasury_state_acct = &accounts[0];
    let sender_holding = &accounts[1];
    let vault_holding = &accounts[2];

    // -- Build chained call to Token::Transfer -----------------------------------
    // Token instruction format: [0x01 || amount (16 bytes LE) || 0x00 x6] = 23 bytes
    let mut token_ix_bytes = vec![0u8; 23];
    token_ix_bytes[0] = 0x01;
    token_ix_bytes[1..17].copy_from_slice(&amount.to_le_bytes());

    let instruction_data = risc0_zkvm::serde::to_vec(&token_ix_bytes).unwrap();

    // Sender is already authorized by user signature; no PDA needed for vault (receiver)
    let chained_call = ChainedCall {
        program_id: *token_program_id,
        instruction_data,
        pre_states: vec![sender_holding.clone(), vault_holding.clone()],
        pda_seeds: vec![],
    };

    // Post states for all 3 accounts (unchanged — Token handles mutations via chained call)
    let treasury_post = AccountPostState::new(treasury_state_acct.account.clone());
    let sender_post = AccountPostState::new(sender_holding.account.clone());
    let vault_post = AccountPostState::new(vault_holding.account.clone());

    (
        vec![treasury_post, sender_post, vault_post],
        vec![chained_call],
    )
}
