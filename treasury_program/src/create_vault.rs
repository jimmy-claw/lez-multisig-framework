use nssa_core::account::{Account, AccountWithMetadata};
use nssa_core::program::{AccountPostState, ChainedCall, ProgramId};
use treasury_core::{TreasuryState, vault_holding_pda_seed};

/// Handle the `CreateVault` instruction.
///
/// Accounts: [treasury_state, token_definition, vault_holding]
pub fn handle(
    accounts: &[AccountWithMetadata],
    token_name: &[u8; 6],
    initial_supply: u128,
    token_program_id: &ProgramId,
    authorized_accounts: &Vec<[u8; 32]>,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() == 3, "CreateVault requires exactly 3 accounts");
    assert!(!authorized_accounts.is_empty(), "At least one authorized account required");

    let treasury_state_acct = &accounts[0];
    let token_definition = &accounts[1];
    let vault_holding = &accounts[2];

    // -- 1. Update treasury state -----------------------------------------------
    let is_first_time = treasury_state_acct.account == Account::default();
    let mut state: TreasuryState = if is_first_time {
        TreasuryState::default()
    } else {
        let data: Vec<u8> = treasury_state_acct.account.data.clone().into();
        borsh::from_slice(&data).expect("failed to deserialize TreasuryState")
    };
    state.vault_count += 1;
    state.authorized_accounts = authorized_accounts.clone();

    let mut treasury_post = treasury_state_acct.account.clone();
    let state_bytes = borsh::to_vec(&state).unwrap();
    treasury_post.data = state_bytes.try_into().expect("TreasuryState too large for Data");

    let treasury_post_state = if is_first_time {
        AccountPostState::new_claimed(treasury_post)
    } else {
        AccountPostState::new(treasury_post)
    };

    // -- 2. Post states for all accounts ----------------------------------------
    let token_def_post = AccountPostState::new(token_definition.account.clone());
    let vault_post = AccountPostState::new(vault_holding.account.clone());

    // -- 3. Build chained call to Token::NewFungibleDefinition ------------------
    let mut token_ix_bytes = vec![0u8; 23];
    token_ix_bytes[0] = 0x00;
    token_ix_bytes[1..17].copy_from_slice(&initial_supply.to_le_bytes());
    token_ix_bytes[17..23].copy_from_slice(token_name);

    let instruction_data = risc0_zkvm::serde::to_vec(&token_ix_bytes).unwrap();

    let mut vault_holding_authorized = vault_holding.clone();
    vault_holding_authorized.is_authorized = true;

    let chained_call = ChainedCall {
        program_id: *token_program_id,
        instruction_data,
        pre_states: vec![token_definition.clone(), vault_holding_authorized],
        pda_seeds: vec![vault_holding_pda_seed(&token_definition.account_id)],
    };

    (
        vec![treasury_post_state, token_def_post, vault_post],
        vec![chained_call],
    )
}
