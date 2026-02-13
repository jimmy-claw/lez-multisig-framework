//! Handler for Deposit — receives tokens from external sender into treasury vault.

use nssa_core::account::{AccountPostState, AccountWithMetadata};
use nssa_core::program::{ChainedCall, InstructionData, ProgramOutput};
use nssa_core::program::Program;

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
        return ProgramOutput::error(format!(
            "Deposit requires 3 accounts (treasury_state, sender, vault), got {}",
            accounts.len()
        ));
    }

    let treasury_state = &mut accounts[0];
    let sender = &mut accounts[1];
    let vault_holding = &mut accounts[2];

    // Treasury state accessed but unchanged
    treasury_state.post_state = AccountPostState::new(treasury_state.account.clone());

    // Sender is authorized by the user's signature (not a PDA)
    sender.post_state = AccountPostState::new(sender.account.clone());

    // Vault is the receiver - mark as accessed
    vault_holding.post_state = AccountPostState::new(vault_holding.account.clone());

    // Build chained call to Token program
    // Sender authorizes the transfer, vault receives
    let token_program_id = Program::token().id();
    let instruction_data = build_transfer_instruction(amount);
    
    let chained_call = ChainedCall {
        program_id: token_program_id,
        instruction_data,
        pre_states: vec![sender.account.clone(), vault_holding.account.clone()],
        pda_seeds: vec![], // No PDA seeds - sender is authorized by signature, vault is receiver
    };

    ProgramOutput {
        instruction_data: vec![],
        pre_states: accounts.to_vec(),
        post_states: vec![
            treasury_state.post_state.clone(),
            sender.post_state.clone(),
            vault_holding.post_state.clone(),
        ],
        chained_calls: vec![chained_call],
    }
}
