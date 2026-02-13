//! Deploy treasury and create vault

use nssa::{
    AccountId, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use wallet::WalletCore;

#[tokio::main]
async fn main() {
    let wallet_core = WalletCore::from_env().unwrap();

    let program_path = std::env::args_os().nth(1).unwrap().into_string().unwrap();
    let account_id: AccountId = std::env::args_os().nth(2).unwrap().into_string().unwrap().parse().unwrap();

    let bytecode = std::fs::read(&program_path).unwrap();
    let program = Program::new(bytecode).unwrap();

    // Instruction = 0 means CreateVault
    let instruction: u8 = 0;

    let nonces = vec![];
    let signing_keys = [];
    let message = Message::try_new(program.id(), vec![account_id], nonces, instruction).unwrap();
    let witness_set = WitnessSet::for_message(&message, &signing_keys);
    let tx = PublicTransaction::new(message, witness_set);

    let _response = wallet_core
        .sequencer_client
        .send_tx_public(tx)
        .await
        .unwrap();

    println!("✅ Treasury CreateVault executed!");
}
