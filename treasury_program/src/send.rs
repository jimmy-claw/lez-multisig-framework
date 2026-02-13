use nssa_core::account::{AccountId, AccountWithMetadata};
use nssa_core::program::{AccountPostState, ChainedCall, ProgramId};
use treasury_core::vault_holding_pda_seed;

/// Handle the `Send` instruction.
///
/// Accounts: [treasury_state, vault_holding, recipient]
pub fn handle(
    accounts: &[AccountWithMetadata],
    amount: u128,
    token_program_id: &ProgramId,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() == 3, "Send requires exactly 3 accounts");

    let treasury_state_acct = &accounts[0];
    let vault_holding = &accounts[1];
    let recipient = &accounts[2];

    // -- 1. Extract token definition_id from vault_holding data -----------------
    // TokenHolding format: [account_type(1) || definition_id(32) || balance(16)] = 49 bytes
    let vault_data: Vec<u8> = vault_holding.account.data.clone().into();
    assert!(
        vault_data.len() >= 33,
        "vault_holding data too short to read definition_id (len={})",
        vault_data.len()
    );
    let mut def_id_bytes = [0u8; 32];
    def_id_bytes.copy_from_slice(&vault_data[1..33]);
    let definition_id = AccountId::new(def_id_bytes);

    // -- 2. Build chained call to Token::Transfer --------------------------------
    // Token instruction format: [0x01 || amount (16 bytes LE) || 0x00 x6] = 23 bytes
    let mut token_ix_bytes = vec![0u8; 23];
    token_ix_bytes[0] = 0x01;
    token_ix_bytes[1..17].copy_from_slice(&amount.to_le_bytes());

    let instruction_data = risc0_zkvm::serde::to_vec(&token_ix_bytes).unwrap();

    // vault_holding needs is_authorized = true for PDA authorization
    let mut vault_authorized = vault_holding.clone();
    vault_authorized.is_authorized = true;

    let chained_call = ChainedCall {
        program_id: *token_program_id,
        instruction_data,
        pre_states: vec![vault_authorized, recipient.clone()],
        pda_seeds: vec![vault_holding_pda_seed(&definition_id)],
    };

    // Post states for all 3 accounts (unchanged — Token handles mutations via chained call)
    let treasury_post = AccountPostState::new(treasury_state_acct.account.clone());
    let vault_post = AccountPostState::new(vault_holding.account.clone());
    let recipient_post = AccountPostState::new(recipient.account.clone());

    (
        vec![treasury_post, vault_post, recipient_post],
        vec![chained_call],
    )
}
