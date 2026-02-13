//! Handler for CreateVault — creates a token definition and mints to treasury vault.

use nssa_core::account::{Account, AccountPostState, AccountWithMetadata};
use nssa_core::program::{ChainedCall, InstructionData, PdaSeed, ProgramId, ProgramOutput};
use nssa_core::program::Program;
use treasury_core::{compute_vault_holding_pda, treasury_state_pda_seed, TreasuryState};

/// Token instruction: [0x00 || total_supply (16 bytes LE) || name (6 bytes)]
fn build_token_instruction(total_supply: u128, name: &str) -> InstructionData {
    let mut name_bytes = [0u8; 6];
    for (i, byte) in name.as_bytes().iter().take(6).enumerate() {
        name_bytes[i] = *byte;
    }
    
    let mut instruction = vec![0u8; 23];
    instruction[1..17].copy_from_slice(&total_supply.to_le_bytes());
    instruction[17..].copy_from_slice(&name_bytes);
    
    // Convert bytes to u32 words
    instruction
        .chunks(4)
        .map(|chunk| {
            let mut word = [0u8; 4];
            word.copy_from_slice(chunk);
            u32::from_le_bytes(word)
        })
        .collect()
}

pub fn handle(
    accounts: &mut [AccountWithMetadata],
    treasury_program_id: &ProgramId,
    token_name: &str,
    initial_supply: u128,
) -> ProgramOutput {
    if accounts.len() != 3 {
        return ProgramOutput::error(format!(
            "CreateVault requires 3 accounts (treasury_state, token_def, vault), got {}",
            accounts.len()
        ));
    }

    let treasury_state = &mut accounts[0];
    let token_definition = &mut accounts[1];
    let vault_holding = &mut accounts[2];

    // Update treasury state
    let mut state = TreasuryState::try_from_slice(&treasury_state.account.data)
        .unwrap_or_default();
    state.vault_count += 1;
    treasury_state.account.data = borsh::to_vec(&state).unwrap();
    treasury_state.post_state = AccountPostState::new(treasury_state.account.clone());

    // Claim token definition account
    token_definition.post_state = AccountPostState::new_claimed(token_definition.account.clone());

    // Claim vault holding account and mark as authorized
    vault_holding.is_authorized = true;
    vault_holding.post_state = AccountPostState::new_claimed(vault_holding.account.clone());

    // Build chained call to Token program
    let token_program_id = Program::token().id();
    let token_def_id = token_definition.account_id;
    let vault_pda_id = compute_vault_holding_pda(treasury_program_id, &token_def_id);
    
    // Create token definition account (will be created by Token program)
    let token_def_account = Account::default();
    
    // Create vault account (will hold the minted tokens)
    let vault_account = Account::default();
    
    let instruction_data = build_token_instruction(initial_supply, token_name);
    
    let chained_call = ChainedCall {
        program_id: token_program_id,
        instruction_data,
        pre_states: vec![token_def_account, vault_account],
        pda_seeds: vec![vault_holding_pda_seed(&token_def_id)],
    };

    ProgramOutput {
        instruction_data: vec![],
        pre_states: accounts.to_vec(),
        post_states: vec![
            treasury_state.post_state.clone(),
            token_definition.post_state.clone(),
            vault_holding.post_state.clone(),
        ],
        chained_calls: vec![chained_call],
    }
}
