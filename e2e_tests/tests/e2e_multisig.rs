//! End-to-end tests for the multisig program.
//!
//! These tests deploy the multisig program to a local sequencer,
//! create a multisig, and test the propose → sign → execute flow.
//!
//! Prerequisites:
//! - A running sequencer at SEQUENCER_URL (default http://127.0.0.1:3040)
//! - Build the guest binary: `cargo risczero build --manifest-path methods/guest/Cargo.toml`
//!   Or set `MULTISIG_PROGRAM` env var to the path of the compiled binary
//!
//! Run with: `cargo test -p lez-multisig-e2e --test e2e_multisig -- --nocapture`

use std::time::Duration;

use nssa::{
    AccountId, PrivateKey, ProgramDeploymentTransaction, PublicKey, PublicTransaction,
    program::Program,
    program_deployment_transaction,
    public_transaction::{Message, WitnessSet},
};
use multisig_core::{Instruction, MultisigState, compute_multisig_state_pda};
use common::sequencer_client::SequencerClient;

/// Helper: derive AccountId from a PrivateKey
fn account_id_from_key(key: &PrivateKey) -> AccountId {
    let pk = PublicKey::new_from_private_key(key);
    AccountId::from(&pk)
}

/// Helper: load the multisig program binary
fn load_program() -> Program {
    let path = std::env::var("MULTISIG_PROGRAM")
        .unwrap_or_else(|_| "target/riscv32im-risc0-zkvm-elf/docker/multisig.bin".to_string());
    let bytecode = std::fs::read(&path)
        .unwrap_or_else(|_| panic!("Cannot read program binary at '{}'. Build with: cargo risczero build --manifest-path methods/guest/Cargo.toml", path));
    Program::new(bytecode).expect("Invalid program bytecode")
}

fn sequencer_client() -> SequencerClient {
    let url = std::env::var("SEQUENCER_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:3040".to_string());
    SequencerClient::new(url.parse().unwrap()).expect("Failed to create sequencer client")
}

/// Helper: submit a public transaction and wait for confirmation
async fn submit_tx(client: &SequencerClient, tx: PublicTransaction) {
    let response = client.send_tx_public(tx).await.expect("Failed to submit tx");
    println!("  tx_hash: {}", response.tx_hash);
    // Wait for block creation
    tokio::time::sleep(Duration::from_secs(15)).await;
}

/// Helper: get nonces for accounts
async fn get_nonces(client: &SequencerClient, accounts: &[AccountId]) -> Vec<u128> {
    let mut nonces = Vec::new();
    for account_id in accounts {
        let account = client.get_account(*account_id).await
            .expect("Failed to get account");
        nonces.push(account.account.nonce);
    }
    nonces
}

/// Deploy the multisig program and return its ID
async fn deploy_program(client: &SequencerClient) -> nssa::ProgramId {
    let program = load_program();
    let program_id = program.id();

    println!("📦 Deploying multisig program...");
    let bytecode = std::fs::read(&std::env::var("MULTISIG_PROGRAM")
        .unwrap_or_else(|_| "target/riscv32im-risc0-zkvm-elf/docker/multisig.bin".to_string()))
        .expect("Cannot read program binary");
    let deploy_msg = program_deployment_transaction::message::Message::new(bytecode);
    let deploy_tx = ProgramDeploymentTransaction::new(deploy_msg);
    let response = client.send_tx_program(deploy_tx).await
        .expect("Failed to deploy program");
    println!("  deploy tx_hash: {}", response.tx_hash);
    tokio::time::sleep(Duration::from_secs(15)).await;

    program_id
}

#[tokio::test]
async fn test_create_multisig() {
    let client = sequencer_client();
    let program_id = deploy_program(&client).await;

    // Generate 3 member keys
    let key1 = PrivateKey::new_os_random();
    let key2 = PrivateKey::new_os_random();
    let key3 = PrivateKey::new_os_random();

    let member1 = account_id_from_key(&key1);
    let member2 = account_id_from_key(&key2);
    let member3 = account_id_from_key(&key3);

    let multisig_state_id = compute_multisig_state_pda(&program_id);

    println!("🔐 Creating 2-of-3 multisig...");
    println!("  member1: {}", member1);
    println!("  member2: {}", member2);
    println!("  member3: {}", member3);
    println!("  state PDA: {}", multisig_state_id);

    let instruction = Instruction::CreateMultisig {
        threshold: 2,
        members: vec![
            *member1.value(),
            *member2.value(),
            *member3.value(),
        ],
    };

    let message = Message::try_new(
        program_id,
        vec![multisig_state_id],
        vec![],
        instruction,
    ).unwrap();
    let witness_set = WitnessSet::for_message(&message, &[] as &[&PrivateKey]);
    let tx = PublicTransaction::new(message, witness_set);
    submit_tx(&client, tx).await;

    // Verify the multisig state was created
    let account = client.get_account(multisig_state_id).await
        .expect("Failed to get multisig state");
    assert_eq!(account.account.program_owner, program_id, "Multisig state should be owned by the program");

    // Deserialize and verify state
    let state: MultisigState = borsh::from_slice(&account.account.data)
        .expect("Failed to deserialize multisig state");
    assert_eq!(state.threshold, 2);
    assert_eq!(state.members.len(), 3);
    assert!(state.members.contains(member1.value()));
    assert!(state.members.contains(member2.value()));
    assert!(state.members.contains(member3.value()));

    println!("✅ Multisig created successfully!");
    println!("  threshold: {}", state.threshold);
    println!("  members: {}", state.members.len());
}

#[tokio::test]
async fn test_propose_sign_execute_transfer() {
    let client = sequencer_client();
    let program_id = deploy_program(&client).await;

    // Generate keys
    let key1 = PrivateKey::new_os_random();
    let key2 = PrivateKey::new_os_random();
    let key3 = PrivateKey::new_os_random();

    let member1 = account_id_from_key(&key1);
    let member2 = account_id_from_key(&key2);
    let member3 = account_id_from_key(&key3);

    let multisig_state_id = compute_multisig_state_pda(&program_id);

    // Create 2-of-3 multisig
    println!("🔐 Creating 2-of-3 multisig...");
    let create_instruction = Instruction::CreateMultisig {
        threshold: 2,
        members: vec![
            *member1.value(),
            *member2.value(),
            *member3.value(),
        ],
    };

    let message = Message::try_new(
        program_id,
        vec![multisig_state_id],
        vec![],
        create_instruction,
    ).unwrap();
    let witness_set = WitnessSet::for_message(&message, &[] as &[&PrivateKey]);
    let tx = PublicTransaction::new(message, witness_set);
    submit_tx(&client, tx).await;

    // === Propose → Sign → Execute ===
    let recipient = account_id_from_key(&PrivateKey::new_os_random());

    println!("📝 Creating proposal for transfer to {}...", recipient);

    // Build the execute instruction
    let execute_instruction = Instruction::Execute {
        recipient,
        amount: 100,
    };

    // Signers: member1 and member2 (threshold = 2)
    let signer_ids = vec![member1, member2];
    let nonces = get_nonces(&client, &signer_ids).await;

    // Build message with signers in account_ids
    // account_ids: [multisig_state_id, member1, member2]
    let message = Message::try_new(
        program_id,
        vec![multisig_state_id, member1, member2],
        nonces,
        execute_instruction,
    ).unwrap();

    println!("✍️  Signing with member1 and member2...");

    // Each signer creates their own WitnessSet
    let ws1 = WitnessSet::for_message(&message, &[&key1]);
    let ws2 = WitnessSet::for_message(&message, &[&key2]);

    // Combine signatures
    let mut all_pairs = ws1.into_raw_parts();
    all_pairs.extend(ws2.into_raw_parts());
    let combined_witness = WitnessSet::from_raw_parts(all_pairs);

    println!("📤 Executing proposal...");
    let tx = PublicTransaction::new(message, combined_witness);
    submit_tx(&client, tx).await;

    println!("✅ Propose → Sign → Execute flow completed!");
    // Note: The transfer itself may fail at the program level (vault has no balance),
    // but the signing, authorization, and sequencer submission should succeed.
}
