//! Handler for Send — transfers tokens from treasury vault to a recipient.

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall, InstructionData, ProgramId, ProgramOutput};
use treasury_core::Instruction;

/// Token transfer instruction: [0x01 || amount (16 bytes LE)]
fn build_transfer_instruction(amount: u128) -> InstructionData {
    let mut instruction = vec![0u8; 17];
    instruction[0] = 0x01;
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

pub fn handle(accounts: &mut [AccountWithMetadata], instruction: &Instruction) -> ProgramOutput {
    if accounts.len() != 3 {
        return ProgramOutput {
            instruction_data: vec![],
            pre_states: accounts.to_vec(),
            post_states: vec![],
            chained_calls: vec![],
        };
    }

    // Parse: [variant: 1][amount: 16 bytes][program_id: 32 bytes]
    let data = &instruction.0[1..];
    let amount = u128::from_le_bytes(data[0..16].try_into().unwrap());
    
    let id_bytes = &data[16..48];
    let mut token_program_id = [0u32; 8];
    for i in 0..8 {
        token_program_id[i] = u32::from_le_bytes(id_bytes[i*4..i*4+4].try_into().unwrap());
    }

    // Read data first to avoid borrow issues
    let treasury_data = accounts[0].account.clone();
    let vault_data = accounts[1].account.clone();
    let recipient_data = accounts[2].account.clone();
    let vault_id = accounts[1].account_id;
    let recipient_id = accounts[2].account_id;

    // Build chained call to Token program
    let instruction_data = build_transfer_instruction(amount);
    
    let vault_meta = AccountWithMetadata::new(vault_data.clone(), true, vault_id);
    let recipient_meta = AccountWithMetadata::new(recipient_data.clone(), false, recipient_id);
    
    let chained_call = ChainedCall {
        program_id: token_program_id,
        instruction_data,
        pre_states: vec![vault_meta, recipient_meta],
        pda_seeds: vec![],
    };

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
