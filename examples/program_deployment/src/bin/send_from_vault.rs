//! Example: Send tokens from the treasury vault to a recipient.
//!
//! Usage:
//!   cargo run --bin send_from_vault \
//!     <path/to/treasury.bin> \
//!     <path/to/token.bin> \
//!     <token_definition_account_id> \
//!     <recipient_account_id> \
//!     <amount>
//!
//! The treasury_state and vault_holding PDA account IDs are computed
//! automatically from the treasury program ID and token definition ID.

use nssa::{
    AccountId, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use treasury_core::{compute_treasury_state_pda, compute_vault_holding_pda, Instruction};
use wallet::WalletCore;

#[tokio::main]
async fn main() {
    // Initialize wallet
    let wallet_core = WalletCore::from_env().unwrap();

    // Parse arguments
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

    // Load the treasury program to get its ID
    let treasury_bytecode: Vec<u8> = std::fs::read(&treasury_bin_path).unwrap();
    let treasury_program = Program::new(treasury_bytecode).unwrap();
    let treasury_program_id = treasury_program.id();

    // Load token program to get its ID
    let token_bytecode: Vec<u8> = std::fs::read(&token_bin_path).unwrap();
    let token_program = Program::new(token_bytecode).unwrap();
    let token_program_id = token_program.id();

    // Compute PDA account IDs automatically
    let treasury_state_id = compute_treasury_state_pda(&treasury_program_id);
    let vault_holding_id = compute_vault_holding_pda(&treasury_program_id, &token_def_id);

    println!("Treasury state PDA:     {}", treasury_state_id);
    println!("Vault holding PDA:      {}", vault_holding_id);
    println!("Recipient:              {}", recipient_id);
    println!("Amount:                 {}", amount);

    // Build the Send instruction
    let instruction = Instruction::Send {
        amount,
        token_program_id,
    };

    // Message::try_new serializes automatically
    let message = Message::try_new(
        treasury_program_id,
        account_ids,
        nonces,
        instruction,
    )
    .unwrap();
    let witness_set = WitnessSet::for_message(&message, &signing_keys);
    let tx = PublicTransaction::new(message, witness_set);

    let _response = wallet_core
        .sequencer_client
        .send_tx_public(tx)
        .await
        .unwrap();

    println!("\n✅ Send transaction submitted!");
    println!("   {} tokens sent from vault to {}.", amount, recipient_id);
}
