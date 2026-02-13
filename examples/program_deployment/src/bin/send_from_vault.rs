use nssa::{
    AccountId, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use treasury_core::{Instruction, compute_treasury_state_pda, compute_vault_holding_pda};
use wallet::WalletCore;

#[tokio::main]
async fn main() {
    let wallet_core = WalletCore::from_env().unwrap();

    // Args: <treasury.bin> <token.bin> <token_def_id> <recipient_id> <amount> <signer_id> <signer_private_key>
    let treasury_path = std::env::args_os().nth(1)
        .expect("Usage: send_from_vault <treasury.bin> <token.bin> <token_def_id> <recipient_id> <amount> <signer_id> <signer_private_key>")
        .into_string().unwrap();
    let token_path = std::env::args_os().nth(2)
        .expect("Missing <token.bin> path")
        .into_string().unwrap();
    let token_def_id: AccountId = std::env::args_os().nth(3)
        .expect("Missing <token_definition_account_id>")
        .into_string().unwrap()
        .parse().unwrap();
    let recipient_id: AccountId = std::env::args_os().nth(4)
        .expect("Missing <recipient_account_id>")
        .into_string().unwrap()
        .parse().unwrap();
    let amount: u128 = std::env::args_os().nth(5)
        .expect("Missing <amount>")
        .into_string().unwrap()
        .parse().unwrap();
    let signer_id: AccountId = std::env::args_os().nth(6)
        .expect("Missing <signer_account_id> — must be an authorized account from CreateVault")
        .into_string().unwrap()
        .parse().unwrap();
    let signer_private_key = std::env::args_os().nth(7)
        .expect("Missing <signer_private_key> — private key for the signer account")
        .into_string().unwrap();

    // Load programs to get their IDs
    let treasury_bytecode: Vec<u8> = std::fs::read(&treasury_path).unwrap();
    let treasury_program = Program::new(treasury_bytecode).unwrap();
    let treasury_program_id = treasury_program.id();

    let token_bytecode: Vec<u8> = std::fs::read(&token_path).unwrap();
    let token_program = Program::new(token_bytecode).unwrap();
    let token_program_id = token_program.id();

    // Compute PDA account IDs
    let treasury_state_id = compute_treasury_state_pda(&treasury_program_id);
    let vault_holding_id = compute_vault_holding_pda(&treasury_program_id, &token_def_id);

    println!("Treasury state PDA:     {}", treasury_state_id);
    println!("Vault holding PDA:      {}", vault_holding_id);
    println!("Recipient:              {}", recipient_id);
    println!("Signer:                 {}", signer_id);
    println!("Amount:                 {}", amount);

    // Build the Send instruction
    let instruction = Instruction::Send {
        amount,
        token_program_id,
    };

    // Include signer_id as the 4th account — Send checks it's authorized
    let account_ids = vec![treasury_state_id, vault_holding_id, recipient_id, signer_id];

    // Parse the signer's private key for signing
    let signer_key_bytes: [u8; 32] = hex::decode(&signer_private_key)
        .expect("Invalid hex for signer private key")
        .try_into()
        .expect("Private key must be 32 bytes");
    let signing_keys = [signer_key_bytes];

    // Signer's nonce (need to match current on-chain nonce)
    let nonces = vec![0u128]; // TODO: fetch actual nonce

    let message = Message::try_new(
        treasury_program_id,
        account_ids,
        nonces,
        instruction,
    ).unwrap();
    let witness_set = WitnessSet::for_message(&message, &signing_keys);
    let tx = PublicTransaction::new(message, witness_set);

    let _response = wallet_core
        .sequencer_client
        .send_tx_public(tx)
        .await
        .unwrap();

    println!("\n✅ Send transaction submitted!");
    println!("   {} tokens sent from vault.", amount);
}
