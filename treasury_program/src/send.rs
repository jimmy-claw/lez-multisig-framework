use nssa_core::account::{AccountId, AccountWithMetadata};
use nssa_core::program::{AccountPostState, ChainedCall, ProgramId};
use treasury_core::{TreasuryState, vault_holding_pda_seed};

/// Handle the `Send` instruction.
///
/// Accounts: [treasury_state, vault_holding, recipient, signer_account]
///
/// The signer_account (accounts[3]) must be one of the authorized_accounts
/// stored in TreasuryState, and must have is_authorized == true (i.e., the
/// transaction was signed by the corresponding key).
pub fn handle(
    accounts: &[AccountWithMetadata],
    amount: u128,
    token_program_id: &ProgramId,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 4, "Send requires at least 4 accounts: [treasury_state, vault_holding, recipient, signer]");

    let treasury_state_acct = &accounts[0];
    let vault_holding = &accounts[1];
    let recipient = &accounts[2];
    let signer = &accounts[3];

    // -- 1. Authorization check -------------------------------------------------
    let state_data: Vec<u8> = treasury_state_acct.account.data.clone().into();
    let state: TreasuryState = borsh::from_slice(&state_data)
        .expect("failed to deserialize TreasuryState");

    // Check that signer is in authorized_accounts
    let signer_bytes = *signer.account_id.value();
    assert!(
        state.authorized_accounts.iter().any(|a| *a == signer_bytes),
        "Signer is not an authorized account"
    );

    // Check that signer actually signed the transaction
    assert!(
        signer.is_authorized,
        "Signer account is not authorized (transaction not signed by this key)"
    );

    // -- 2. Extract token definition_id from vault_holding data -----------------
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

    // -- 3. Build chained call to Token::Transfer --------------------------------
    let mut token_ix_bytes = vec![0u8; 23];
    token_ix_bytes[0] = 0x01;
    token_ix_bytes[1..17].copy_from_slice(&amount.to_le_bytes());

    let instruction_data = risc0_zkvm::serde::to_vec(&token_ix_bytes).unwrap();

    let mut vault_authorized = vault_holding.clone();
    vault_authorized.is_authorized = true;

    let chained_call = ChainedCall {
        program_id: *token_program_id,
        instruction_data,
        pre_states: vec![vault_authorized, recipient.clone()],
        pda_seeds: vec![vault_holding_pda_seed(&definition_id)],
    };

    // Post states for all accounts (unchanged)
    let post_states: Vec<AccountPostState> = accounts.iter()
        .map(|a| AccountPostState::new(a.account.clone()))
        .collect();

    (post_states, vec![chained_call])
}
