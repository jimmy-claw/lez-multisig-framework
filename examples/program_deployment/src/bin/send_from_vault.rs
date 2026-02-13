//! Example: Send tokens from the treasury vault to a recipient.

use nssa::{
    AccountId, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use treasury_core::{compute_treasury_state_pda, compute_vault_holding_pda, Instruction};
use wallet::WalletCore;

#[tokio::main]
async fn main() {
    let wallet_core = WalletCore::from_env().unwrap();

    let treasury_bin_path = std::env::args_os()
        .nth(1)
        .expect("Usage: send_from_vault <treasury.bin> <token.bin> <token_def_id> <recipient_id> <amount>")
        .into_string()
        .unwrap();
    let token_bin_path = std::env::args_os()
        .nth(2)
        .expect("Missing <token.bin> path")
        .into_string()
        .unwrap();
    let token_def_id: AccountId = std::env::args_os()
        .nth(3)
        .expect("Missing <token_definition_account_id>")
        .into_string()
        .unwrap()
        .parse()
        .unwrap();
    let recipient_id: AccountId = std::env::args_os()
        .nth(4)
        .expect("Missing <recipient_account_id>")
        .into_string()
        .unwrap()
        .parse()
        .unwrap();
    let amount: u128 = std::env::args_os()
        .nth(5)
        .expect("Missing <amount>")
        .into_string()
        .unwrap()
        .parse()
        .unwrap();

    let treasury_bytecode: Vec<u8> = std::fs::read(&treasury_bin_path).unwrap();
    let treasury_program = Program::new(treasury_bytecode).unwrap();
    let treasury_program_id = treasury_program.id();

    let token_bytecode: Vec<u8> = std::fs::read(&token_bin_path).unwrap();
    let token_program = Program::new(token_bytecode).unwrap();
    let token_program_id = token_program.id();

    let treasury_state_id = compute_treasury_state_pda(&treasury_program_id);
    let vault_holding_id = compute_vault_holding_pda(&treasury_program_id, &token_def_id);

    println!("Treasury state PDA:     {}", treasury_state_id);
    println!("Vault holding PDA:      {}", vault_holding_id);
    println!("Recipient:              {}", recipient_id);
    println!("Amount:                 {}", amount);

    // Build instruction
    let instruction = Instruction::send(amount, token_program_id);

    let account_ids = vec![treasury_state_id, vault_holding_id, recipient_id];
    let nonces = vec![];
    let signing_keys = [];
    let message = Message::try_new(treasury_program_id, account_ids, nonces, instruction).unwrap();
    let witness_set = WitnessSet::for_message(&message, &signing_keys);
    let tx = PublicTransaction::new(message, witness_set);

    let _response = wallet_core
        .sequencer_client
        .send_tx_public(tx)
        .await
        .unwrap();

    println!("\n✅ Send transaction submitted!");
}
