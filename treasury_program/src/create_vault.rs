//! Handler for CreateVault — creates a token definition and mints to treasury vault.

use borsh::BorshDeserialize;
use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, InstructionData, PdaSeed, ProgramId, ProgramOutput};
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
    
    instruction
        .chunks(4)
        .map(|chunk| {
            let mut word = [0u8; 4];
            word.copy_from_slice(chunk);
            u32::from_le_bytes(word)
        })
        .collect()
}

pub fn handle(accounts: &mut [AccountWithMetadata], instruction: u128) -> ProgramOutput {
    if accounts.len() != 3 {
        return ProgramOutput {
            instruction_data: vec![],
            pre_states: accounts.to_vec(),
            post_states: vec![],
            chained_calls: vec![],
        };
    }

    // For now, just claim the accounts but don't actually chain
    // We need to extract the token_program_id from the instruction first
    
    // Read data from accounts first (avoid borrow issues)
    let treasury_data = accounts[0].account.data.clone();
    let token_def_data = accounts[1].account.clone();
    let vault_data = accounts[2].account.clone();

    // Update treasury state
    let mut state = TreasuryState::try_from_slice(&*treasury_data).unwrap_or_default();
    state.vault_count += 1;
    accounts[0].account.data = borsh::to_vec(&state).unwrap().try_into().unwrap();

    let treasury_post = AccountPostState::new(accounts[0].account.clone());
    let token_def_post = AccountPostState::new_claimed(token_def_data);
    let vault_post = AccountPostState::new_claimed(vault_data);

    // Return without chained call for now - just test basic execution
    ProgramOutput {
        instruction_data: vec![],
        pre_states: accounts.to_vec(),
        post_states: vec![treasury_post, token_def_post, vault_post],
        chained_calls: vec![],
    }
}
