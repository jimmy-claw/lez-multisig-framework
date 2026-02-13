//! Handler for Send — transfers tokens from treasury vault to a recipient.

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, InstructionData, ProgramOutput};
use nssa::program::Program;

/// Token transfer instruction: [0x01 || amount (16 bytes LE)]
fn build_transfer_instruction(amount: u128) -> InstructionData {
    let mut instruction = vec![0u8; 17];
    instruction[0] = 0x01; // Transfer instruction tag
    instruction[1..17].copy_from_slice(&amount.to_le_bytes());
    
    instruction
        .chunks(4)
        .map(|chunk| {
            let mut word = [0u8; 4];
            word.copy_from_slice(chunk);
            u32::from_le_bytes(word)
        })
        .collect()
}

pub fn handle(accounts: &mut [AccountWithMetadata], amount: u128) -> ProgramOutput {
    if accounts.len() != 3 {
        return ProgramOutput {
            instruction_data: vec![],
            pre_states: accounts.to_vec(),
            post_states: vec![],
            chained_calls: vec![],
        };
    }

    // Read data first to avoid borrow issues
    let treasury_data = accounts[0].account.clone();
    let vault_data = accounts[1].account.clone();
    let recipient_data = accounts[2].account.clone();
    let vault_id = accounts[1].account_id;
    let recipient_id = accounts[2].account_id;

    // Build chained call to Token program
    let token_program_id = Program::token().id();
    let instruction_data = build_transfer_instruction(amount);
    
    // Provide vault and recipient as pre_states
    let vault_meta = AccountWithMetadata::new(vault_data.clone(), true, vault_id);
    let recipient_meta = AccountWithMetadata::new(recipient_data.clone(), false, recipient_id);
    
    let chained_call = ChainedCall {
        program_id: token_program_id,
        instruction_data,
        pre_states: vec![vault_meta, recipient_meta],
        pda_seeds: vec![],
    };

    // Build post_states
    let treasury_post = AccountPostState::new(treasury_data);
    let vault_post = AccountPostState::new(vault_data);
    let recipient_post = AccountPostState::new(recipient_data);

    ProgramOutput {
        instruction_data: vec![],
        pre_states: accounts.to_vec(),
        post_states: vec![treasury_post, vault_post, recipient_post],
        chained_calls: vec![chained_call],
    }
}
