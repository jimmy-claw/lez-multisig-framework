//! End-to-end test for the multisig program (Squads-style on-chain proposals).
//!
//! NOTE: Since there's only one PDA per program, this is a single sequential test
//! that exercises the full lifecycle: create → propose → approve → execute.
//!
//! Prerequisites:
//! - A running sequencer at SEQUENCER_URL (default http://127.0.0.1:3040)
//! - MULTISIG_PROGRAM env var pointing to the compiled guest binary
//! - Fresh sequencer DB (no prior program deployment)
//!
//! Run with: `bash e2e_tests/run_e2e.sh`

use std::time::Duration;

use nssa::{
    AccountId, PrivateKey, ProgramDeploymentTransaction, PublicKey, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use multisig_core::{Instruction, MultisigState, ProposalAction, ProposalStatus, compute_multisig_state_pda};
use common::sequencer_client::SequencerClient;

const BLOCK_WAIT_SECS: u64 = 15;

fn account_id_from_key(key: &PrivateKey) -> AccountId {
    let pk = PublicKey::new_from_private_key(key);
    AccountId::from(&pk)
}

fn load_program_bytecode() -> Vec<u8> {
    let path = std::env::var("MULTISIG_PROGRAM")
        .unwrap_or_else(|_| "target/riscv32im-risc0-zkvm-elf/docker/multisig.bin".to_string());
    std::fs::read(&path)
        .unwrap_or_else(|_| panic!("Cannot read program binary at '{}'", path))
}

fn sequencer_client() -> SequencerClient {
    let url = std::env::var("SEQUENCER_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:3040".to_string());
    SequencerClient::new(url.parse().unwrap()).expect("Failed to create sequencer client")
}

async fn submit_tx(client: &SequencerClient, tx: PublicTransaction) {
    let response = client.send_tx_public(tx).await.expect("Failed to submit tx");
    println!("  tx_hash: {}", response.tx_hash);
    tokio::time::sleep(Duration::from_secs(BLOCK_WAIT_SECS)).await;
}

/// Submit a single-signer transaction
async fn submit_signed(
    client: &SequencerClient,
    program_id: nssa::ProgramId,
    account_ids: Vec<AccountId>,
    signer_key: &PrivateKey,
    nonces: Vec<u128>,
    instruction: Instruction,
) {
    let message = Message::try_new(program_id, account_ids, nonces, instruction).unwrap();
    let witness_set = WitnessSet::for_message(&message, &[signer_key]);
    let tx = PublicTransaction::new(message, witness_set);
    submit_tx(client, tx).await;
}

async fn get_nonce(client: &SequencerClient, account_id: AccountId) -> u128 {
    client.get_account(account_id).await
        .map(|r| r.account.nonce)
        .unwrap_or(0)
}

async fn get_multisig_state(client: &SequencerClient, state_id: AccountId) -> MultisigState {
    let account = client.get_account(state_id).await.expect("Failed to get multisig state");
    let data: Vec<u8> = account.account.data.into();
    borsh::from_slice(&data).expect("Failed to deserialize multisig state")
}

#[tokio::test]
async fn test_full_multisig_lifecycle() {
    let client = sequencer_client();

    // ── Deploy program ──────────────────────────────────────────────────
    let bytecode = load_program_bytecode();
    let program = Program::new(bytecode.clone()).expect("Invalid program");
    let program_id = program.id();

    // Unique create_key per test run — enables multiple multisigs per program
    let create_key: [u8; 32] = *AccountId::from(&PublicKey::new_from_private_key(&PrivateKey::new_os_random())).value();
    let multisig_state_id = compute_multisig_state_pda(&program_id, &create_key);

    println!("📦 Deploying multisig program...");
    let deploy_msg = nssa::program_deployment_transaction::Message::new(bytecode);
    let deploy_tx = ProgramDeploymentTransaction::new(deploy_msg);
    match client.send_tx_program(deploy_tx).await {
        Ok(response) => {
            println!("  deploy tx_hash: {}", response.tx_hash);
            tokio::time::sleep(Duration::from_secs(BLOCK_WAIT_SECS)).await;
        }
        Err(e) => {
            println!("  deploy skipped (likely already exists): {}", e);
        }
    }

    // ── Generate 3 member keys ──────────────────────────────────────────
    let key1 = PrivateKey::new_os_random();
    let key2 = PrivateKey::new_os_random();
    let key3 = PrivateKey::new_os_random();
    let m1 = account_id_from_key(&key1);
    let m2 = account_id_from_key(&key2);
    let m3 = account_id_from_key(&key3);

    println!("\n═══ STEP 1: Create 2-of-3 multisig ═══");
    println!("  Members: {}, {}, {}", m1, m2, m3);
    let instruction = Instruction::CreateMultisig {
        create_key,
        threshold: 2,
        members: vec![*m1.value(), *m2.value(), *m3.value()],
    };
    let message = Message::try_new(program_id, vec![multisig_state_id], vec![], instruction).unwrap();
    let witness_set = WitnessSet::for_message(&message, &[] as &[&PrivateKey]);
    submit_tx(&client, PublicTransaction::new(message, witness_set)).await;

    // Verify on-chain state
    let state = get_multisig_state(&client, multisig_state_id).await;
    assert_eq!(state.threshold, 2, "threshold should be 2");
    assert_eq!(state.members.len(), 3, "should have 3 members");
    assert_eq!(state.transaction_index, 0, "no proposals yet");
    assert!(state.proposals.is_empty(), "no proposals yet");
    println!("  ✅ Multisig created!");

    // ── STEP 2: Member 1 proposes a transfer ────────────────────────────
    println!("\n═══ STEP 2: Member 1 proposes transfer ═══");
    let recipient = account_id_from_key(&PrivateKey::new_os_random());
    let nonce = get_nonce(&client, m1).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m1],
        &key1, vec![nonce],
        Instruction::Propose {
            action: ProposalAction::Transfer { recipient, amount: 100 },
        },
    ).await;

    let state = get_multisig_state(&client, multisig_state_id).await;
    assert_eq!(state.proposals.len(), 1, "should have 1 proposal");
    assert_eq!(state.proposals[0].index, 1);
    assert_eq!(state.proposals[0].approved.len(), 1, "proposer auto-approved");
    assert_eq!(state.proposals[0].status, ProposalStatus::Active);
    println!("  ✅ Proposal #1 created (1/2 approvals)");

    // ── STEP 3: Member 2 approves ──────────────────────────────────────
    println!("\n═══ STEP 3: Member 2 approves proposal #1 ═══");
    let nonce = get_nonce(&client, m2).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m2],
        &key2, vec![nonce],
        Instruction::Approve { proposal_index: 1 },
    ).await;

    let state = get_multisig_state(&client, multisig_state_id).await;
    let proposal = state.get_proposal(1).unwrap();
    assert_eq!(proposal.approved.len(), 2, "should have 2 approvals now");
    assert!(proposal.has_threshold(state.threshold), "threshold reached!");
    println!("  ✅ Proposal #1 has 2/2 approvals — ready to execute!");

    // ── STEP 4: Execute the transfer ────────────────────────────────────
    println!("\n═══ STEP 4: Execute proposal #1 ═══");
    let nonce = get_nonce(&client, m1).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m1],
        &key1, vec![nonce],
        Instruction::Execute { proposal_index: 1 },
    ).await;

    let state = get_multisig_state(&client, multisig_state_id).await;
    assert!(state.proposals.is_empty(), "executed proposals should be cleaned up");
    assert_eq!(state.transaction_index, 1, "transaction index should be 1");
    println!("  ✅ Proposal #1 executed and cleaned up!");

    // ── STEP 5: Propose and reject ──────────────────────────────────────
    println!("\n═══ STEP 5: Member 2 proposes, Members 1 & 3 reject ═══");
    let nonce = get_nonce(&client, m2).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m2],
        &key2, vec![nonce],
        Instruction::Propose {
            action: ProposalAction::Transfer {
                recipient: account_id_from_key(&PrivateKey::new_os_random()),
                amount: 999,
            },
        },
    ).await;

    // Member 1 rejects
    let nonce = get_nonce(&client, m1).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m1],
        &key1, vec![nonce],
        Instruction::Reject { proposal_index: 2 },
    ).await;

    // Member 3 rejects — now 2 rejections, only 1 non-rejector (proposer), can't reach threshold=2
    let nonce = get_nonce(&client, m3).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m3],
        &key3, vec![nonce],
        Instruction::Reject { proposal_index: 2 },
    ).await;

    let state = get_multisig_state(&client, multisig_state_id).await;
    let proposal = state.get_proposal(2).unwrap();
    assert_eq!(proposal.status, ProposalStatus::Rejected, "proposal should be auto-rejected");
    assert_eq!(proposal.rejected.len(), 2);
    println!("  ✅ Proposal #2 rejected (2 rejections, dead proposal)");

    // ── STEP 6: Propose adding a new member ─────────────────────────────
    println!("\n═══ STEP 6: Add a 4th member via proposal ═══");
    let key4 = PrivateKey::new_os_random();
    let m4 = account_id_from_key(&key4);

    let nonce = get_nonce(&client, m1).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m1],
        &key1, vec![nonce],
        Instruction::Propose {
            action: ProposalAction::AddMember { new_member: *m4.value() },
        },
    ).await;

    // Member 3 approves (proposer m1 auto-approved, so now 2/2)
    let nonce = get_nonce(&client, m3).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m3],
        &key3, vec![nonce],
        Instruction::Approve { proposal_index: 3 },
    ).await;

    // Execute
    let nonce = get_nonce(&client, m1).await;
    submit_signed(
        &client, program_id,
        vec![multisig_state_id, m1],
        &key1, vec![nonce],
        Instruction::Execute { proposal_index: 3 },
    ).await;

    let state = get_multisig_state(&client, multisig_state_id).await;
    assert_eq!(state.members.len(), 4, "should have 4 members now");
    assert!(state.is_member(m4.value()), "member 4 should be a member");
    println!("  ✅ Member 4 added! Now 4 members, threshold still 2");

    println!("\n🎉 Full multisig lifecycle test PASSED!");
    println!("   - Create ✅");
    println!("   - Propose + Approve + Execute ✅");
    println!("   - Propose + Reject ✅");
    println!("   - Config change (AddMember) ✅");
}
