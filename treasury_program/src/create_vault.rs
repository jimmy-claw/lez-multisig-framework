//! Handler for CreateVault — creates a token definition and mints to treasury vault.

use borsh::BorshDeserialize;
use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, InstructionData, PdaSeed, ProgramOutput};
use nssa::program::Program;
use treasury_core::TreasuryState;

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
    token_name: &str,
    initial_supply: u128,
) -> ProgramOutput {
    if accounts.len() != 3 {
        return ProgramOutput {
            instruction_data: vec![],
            pre_states: accounts.to_vec(),
            post_states: vec![],
            chained_calls: vec![],
        };
    }

    // Read data from accounts first (avoid borrow issues)
    let treasury_data = accounts[0].account.data.clone();
    let token_def_data = accounts[1].account.clone();
    let vault_data = accounts[2].account.clone();
    let token_def_id = accounts[1].account_id;
    let vault_id = accounts[2].account_id;

    // Update treasury state
    let mut state = TreasuryState::try_from_slice(&*treasury_data).unwrap_or_default();
    state.vault_count += 1;
    accounts[0].account.data = borsh::to_vec(&state).unwrap().try_into().unwrap();

    // Build chained call to Token program
    let token_program_id = Program::token().id();
    let instruction_data = build_token_instruction(initial_supply, token_name);
    
    // For the chained call, we need AccountWithMetadata
    let token_def_meta = AccountWithMetadata::new(token_def_data.clone(), false, token_def_id);
    let vault_meta = AccountWithMetadata::new(vault_data.clone(), true, vault_id);
    
    // PDA seed for the vault
    let vault_pda_seed = PdaSeed::new(*vault_id.value());
    
    let chained_call = ChainedCall {
        program_id: token_program_id,
        instruction_data,
        pre_states: vec![token_def_meta, vault_meta],
        pda_seeds: vec![vault_pda_seed],
    };

    // Build post_states using AccountPostState
    let treasury_post = AccountPostState::new(accounts[0].account.clone());
    let token_def_post = AccountPostState::new_claimed(token_def_data);
    let vault_post = AccountPostState::new_claimed(vault_data);

    ProgramOutput {
        instruction_data: vec![],
        pre_states: accounts.to_vec(),
        post_states: vec![treasury_post, token_def_post, vault_post],
        chained_calls: vec![chained_call],
    }
}
