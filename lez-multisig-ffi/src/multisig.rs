//! Multisig operation implementations for the FFI layer.
//!
//! Each function takes a JSON args string and returns a JSON result string.
//! Transaction building follows the same pattern as registry FFI.
//!
//! Common JSON input fields:
//! - `sequencer_url`: e.g. "http://127.0.0.1:3040"
//! - `wallet_path`:   path to the NSSA wallet directory (sets NSSA_WALLET_HOME_DIR)
//! - `program_id_hex`: 64-char hex string identifying the multisig program binary

use nssa::{
    AccountId, PublicTransaction,
    public_transaction::{Message, WitnessSet},
};
use multisig_core::{
    Instruction, MultisigState, Proposal, ProposalStatus,
    compute_multisig_state_pda, compute_proposal_pda,
};
use serde_json::{Value, json};
use wallet::WalletCore;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn parse_args(args: &str) -> Result<Value, String> {
    serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))
}

fn get_str<'a>(v: &'a Value, key: &str) -> Result<&'a str, String> {
    v[key].as_str().ok_or_else(|| format!("missing field '{}'", key))
}

/// Parse a 64-hex-char program_id string into [u32; 8] (big-endian words).
fn parse_program_id_hex(s: &str) -> Result<nssa::ProgramId, String> {
    let s = s.trim_start_matches("0x");
    if s.len() != 64 {
        return Err(format!("program_id_hex must be 64 hex chars (got {})", s.len()));
    }
    let bytes = hex::decode(s).map_err(|e| format!("invalid hex in program_id: {}", e))?;
    let mut pid = [0u32; 8];
    for (i, chunk) in bytes.chunks(4).enumerate() {
        pid[i] = u32::from_be_bytes(chunk.try_into().unwrap());
    }
    Ok(pid)
}

/// Parse a 64-char hex string into [u8; 32].
fn parse_hex32(s: &str, field: &str) -> Result<[u8; 32], String> {
    let s = s.trim_start_matches("0x");
    if s.len() != 64 {
        return Err(format!("{} must be 64 hex chars (got {})", field, s.len()));
    }
    let bytes = hex::decode(s).map_err(|e| format!("invalid hex in {}: {}", field, e))?;
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(arr)
}

/// Submit a transaction and wait for confirmation.
async fn submit_and_wait(
    client: &common::sequencer_client::SequencerClient,
    tx: PublicTransaction,
) -> Result<String, String> {
    let response = client
        .send_tx_public(tx)
        .await
        .map_err(|e| format!("failed to submit transaction: {}", e))?;

    Ok(response.tx_hash.to_string())
}

/// Build + submit a signed transaction for a multisig instruction.
async fn submit_signed_multisig_tx(
    wallet_core: &WalletCore,
    multisig_program_id: nssa::ProgramId,
    account_ids: Vec<AccountId>,
    signer_id: AccountId,
    instruction: Instruction,
) -> Result<String, String> {
    let nonces = wallet_core
        .get_accounts_nonces(vec![signer_id])
        .await
        .map_err(|e| format!("failed to get nonces: {}", e))?;

    let signing_key = wallet_core
        .storage()
        .user_data
        .get_pub_account_signing_key(signer_id)
        .ok_or_else(|| format!(
            "signing key not found for account {} — is it in your wallet?",
            signer_id
        ))?;

    let message = Message::try_new(multisig_program_id, account_ids, nonces, instruction)
        .map_err(|e| format!("failed to build message: {:?}", e))?;

    let witness_set = WitnessSet::for_message(&message, &[signing_key]);
    let tx = PublicTransaction::new(message, witness_set);

    submit_and_wait(&wallet_core.sequencer_client, tx).await
}

/// Fetch and deserialize a Borsh-encoded account.
async fn fetch_borsh_account<T: borsh::BorshDeserialize>(
    wallet_core: &WalletCore,
    account_id: AccountId,
) -> Result<Option<T>, String> {
    let account = wallet_core
        .get_account_public(account_id)
        .await
        .map_err(|e| format!("failed to fetch account {}: {}", account_id, e))?;
    let data: Vec<u8> = account.data.into();
    if data.is_empty() {
        return Ok(None);
    }
    let decoded = borsh::from_slice::<T>(&data)
        .map_err(|e| format!("failed to deserialize account data: {}", e))?;
    Ok(Some(decoded))
}

/// Load WalletCore with optional wallet_path override.
fn load_wallet(wallet_path: Option<&str>) -> Result<WalletCore, String> {
    if let Some(path) = wallet_path {
        std::env::set_var("NSSA_WALLET_HOME_DIR", path);
    }
    WalletCore::from_env().map_err(|e| format!("failed to load wallet: {}", e))
}

/// Serialize ProposalStatus to string.
fn status_str(status: &ProposalStatus) -> &'static str {
    match status {
        ProposalStatus::Active    => "Active",
        ProposalStatus::Executed  => "Executed",
        ProposalStatus::Rejected  => "Rejected",
        ProposalStatus::Cancelled => "Cancelled",
    }
}

/// Serialize a [u8;32] to hex string.
fn bytes32_to_hex(b: &[u8; 32]) -> String {
    hex::encode(b)
}

/// Serialize a ProgramId ([u32;8]) to hex string.
fn program_id_to_hex(pid: &nssa::ProgramId) -> String {
    pid.iter()
        .flat_map(|w| w.to_be_bytes())
        .map(|b| format!("{:02x}", b))
        .collect()
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Create a new multisig.
///
/// Args JSON:
/// ```json
/// {
///   "sequencer_url":       "http://127.0.0.1:3040",
///   "wallet_path":         "/path/to/wallet",
///   "multisig_program_id": "(64 hex chars)",
///   "account":             "<signer AccountId>",
///   "create_key":          "(64 hex chars — unique key for this multisig)",
///   "threshold":           2,
///   "members":             ["(64 hex — member AccountId bytes)", ...]
/// }
/// ```
pub fn create(args: &str) -> String {
    let v = match parse_args(args) {
        Ok(v) => v,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return json!({"success": false, "error": format!("runtime error: {}", e)}).to_string(),
    };

    rt.block_on(async { create_async(&v).await })
}

async fn create_async(v: &Value) -> String {
    let sequencer_url = match get_str(v, "sequencer_url") {
        Ok(s) => s.to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let wallet_path = v["wallet_path"].as_str();
    let prog_id_hex = match get_str(v, "multisig_program_id") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let account_hex = match get_str(v, "account") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key_hex = match get_str(v, "create_key") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let threshold = match v["threshold"].as_u64() {
        Some(t) if t <= 255 => t as u8,
        _ => return json!({"success": false, "error": "missing or invalid 'threshold' (0-255)"}).to_string(),
    };

    let multisig_program_id = match parse_program_id_hex(prog_id_hex) {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let create_key = match parse_hex32(create_key_hex, "create_key") {
        Ok(k) => k,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    // Parse members array
    let members_json = match v["members"].as_array() {
        Some(a) => a,
        None => return json!({"success": false, "error": "missing 'members' array"}).to_string(),
    };
    let mut members: Vec<[u8; 32]> = Vec::new();
    for (i, m) in members_json.iter().enumerate() {
        let s = match m.as_str() {
            Some(s) => s,
            None => return json!({"success": false, "error": format!("members[{}] is not a string", i)}).to_string(),
        };
        match parse_hex32(s, &format!("members[{}]", i)) {
            Ok(k) => members.push(k),
            Err(e) => return json!({"success": false, "error": e}).to_string(),
        }
    }

    std::env::set_var("NSSA_SEQUENCER_URL", &sequencer_url);

    let wallet_core = match load_wallet(wallet_path) {
        Ok(w) => w,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let signer_id: AccountId = match account_hex.parse() {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": format!("invalid account id: {}", e)}).to_string(),
    };

    let multisig_state_pda = compute_multisig_state_pda(&multisig_program_id, &create_key);

    let instruction = Instruction::CreateMultisig {
        create_key,
        threshold,
        members,
    };

    let account_ids = vec![multisig_state_pda, signer_id];

    match submit_signed_multisig_tx(
        &wallet_core,
        multisig_program_id,
        account_ids,
        signer_id,
        instruction,
    ).await {
        Ok(tx_hash) => json!({
            "success": true,
            "tx_hash": tx_hash,
            "multisig_state_pda": multisig_state_pda.to_string(),
            "create_key": hex::encode(create_key),
        }).to_string(),
        Err(e) => json!({"success": false, "error": e}).to_string(),
    }
}

/// Create a new proposal in a multisig.
///
/// Args JSON:
/// ```json
/// {
///   "sequencer_url":           "http://127.0.0.1:3040",
///   "wallet_path":             "/path/to/wallet",
///   "multisig_program_id":     "(64 hex chars)",
///   "account":                 "<proposer AccountId>",
///   "create_key":              "(64 hex chars)",
///   "target_program_id":       "(64 hex chars)",
///   "target_instruction_data": "(hex-encoded bytes)",
///   "target_account_count":    3,
///   "pda_seeds":               ["(64 hex)", ...],
///   "authorized_indices":      [0, 1]
/// }
/// ```
pub fn propose(args: &str) -> String {
    let v = match parse_args(args) {
        Ok(v) => v,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return json!({"success": false, "error": format!("runtime error: {}", e)}).to_string(),
    };

    rt.block_on(async { propose_async(&v).await })
}

async fn propose_async(v: &Value) -> String {
    let sequencer_url = match get_str(v, "sequencer_url") {
        Ok(s) => s.to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let wallet_path = v["wallet_path"].as_str();
    let prog_id_hex = match get_str(v, "multisig_program_id") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let account_hex = match get_str(v, "account") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key_hex = match get_str(v, "create_key") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let target_prog_hex = match get_str(v, "target_program_id") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let target_data_hex = match get_str(v, "target_instruction_data") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let target_account_count = match v["target_account_count"].as_u64() {
        Some(t) if t <= 255 => t as u8,
        _ => return json!({"success": false, "error": "missing or invalid 'target_account_count'"}).to_string(),
    };

    let multisig_program_id = match parse_program_id_hex(prog_id_hex) {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key = match parse_hex32(create_key_hex, "create_key") {
        Ok(k) => k,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let target_program_id = match parse_program_id_hex(target_prog_hex) {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let target_instruction_data: Vec<u8> = match hex::decode(target_data_hex.trim_start_matches("0x")) {
        Ok(b) => b,
        Err(e) => return json!({"success": false, "error": format!("invalid hex in target_instruction_data: {}", e)}).to_string(),
    };

    // Parse pda_seeds array
    let mut pda_seeds: Vec<[u8; 32]> = Vec::new();
    if let Some(seeds_arr) = v["pda_seeds"].as_array() {
        for (i, s) in seeds_arr.iter().enumerate() {
            let hex_str = match s.as_str() {
                Some(s) => s,
                None => return json!({"success": false, "error": format!("pda_seeds[{}] is not a string", i)}).to_string(),
            };
            match parse_hex32(hex_str, &format!("pda_seeds[{}]", i)) {
                Ok(k) => pda_seeds.push(k),
                Err(e) => return json!({"success": false, "error": e}).to_string(),
            }
        }
    }

    // Parse authorized_indices
    let mut authorized_indices: Vec<u8> = Vec::new();
    if let Some(indices_arr) = v["authorized_indices"].as_array() {
        for (i, idx) in indices_arr.iter().enumerate() {
            match idx.as_u64() {
                Some(n) if n <= 255 => authorized_indices.push(n as u8),
                _ => return json!({"success": false, "error": format!("authorized_indices[{}] invalid", i)}).to_string(),
            }
        }
    }

    std::env::set_var("NSSA_SEQUENCER_URL", &sequencer_url);

    let wallet_core = match load_wallet(wallet_path) {
        Ok(w) => w,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let signer_id: AccountId = match account_hex.parse() {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": format!("invalid account id: {}", e)}).to_string(),
    };

    let multisig_state_pda = compute_multisig_state_pda(&multisig_program_id, &create_key);

    // Fetch current state to get the next proposal index
    let state = match fetch_borsh_account::<MultisigState>(&wallet_core, multisig_state_pda).await {
        Ok(Some(s)) => s,
        Ok(None) => return json!({"success": false, "error": "multisig state account not found — create the multisig first"}).to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let next_index = state.transaction_index + 1;
    let proposal_pda = compute_proposal_pda(&multisig_program_id, &create_key, next_index);

    let instruction = Instruction::Propose {
        target_program_id,
        target_instruction_data: nssa_core::program::InstructionData::new(target_instruction_data),
        target_account_count,
        pda_seeds: pda_seeds.into_iter().map(|s| nssa_core::program::PdaSeed::new(s)).collect(),
        authorized_indices,
    };

    let account_ids = vec![multisig_state_pda, proposal_pda, signer_id];

    match submit_signed_multisig_tx(
        &wallet_core,
        multisig_program_id,
        account_ids,
        signer_id,
        instruction,
    ).await {
        Ok(tx_hash) => json!({
            "success": true,
            "tx_hash": tx_hash,
            "proposal_index": next_index,
            "proposal_pda": proposal_pda.to_string(),
        }).to_string(),
        Err(e) => json!({"success": false, "error": e}).to_string(),
    }
}

/// Approve an existing proposal.
///
/// Args JSON:
/// ```json
/// {
///   "sequencer_url":       "http://127.0.0.1:3040",
///   "wallet_path":         "/path/to/wallet",
///   "multisig_program_id": "(64 hex chars)",
///   "account":             "<approver AccountId>",
///   "create_key":          "(64 hex chars)",
///   "proposal_index":      1
/// }
/// ```
pub fn approve(args: &str) -> String {
    let v = match parse_args(args) {
        Ok(v) => v,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return json!({"success": false, "error": format!("runtime error: {}", e)}).to_string(),
    };

    rt.block_on(async { vote_async(&v, true).await })
}

/// Reject an existing proposal.
pub fn reject(args: &str) -> String {
    let v = match parse_args(args) {
        Ok(v) => v,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return json!({"success": false, "error": format!("runtime error: {}", e)}).to_string(),
    };

    rt.block_on(async { vote_async(&v, false).await })
}

async fn vote_async(v: &Value, is_approve: bool) -> String {
    let sequencer_url = match get_str(v, "sequencer_url") {
        Ok(s) => s.to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let wallet_path = v["wallet_path"].as_str();
    let prog_id_hex = match get_str(v, "multisig_program_id") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let account_hex = match get_str(v, "account") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key_hex = match get_str(v, "create_key") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let proposal_index = match v["proposal_index"].as_u64() {
        Some(i) => i,
        None => return json!({"success": false, "error": "missing 'proposal_index'"}).to_string(),
    };

    let multisig_program_id = match parse_program_id_hex(prog_id_hex) {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key = match parse_hex32(create_key_hex, "create_key") {
        Ok(k) => k,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    std::env::set_var("NSSA_SEQUENCER_URL", &sequencer_url);

    let wallet_core = match load_wallet(wallet_path) {
        Ok(w) => w,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let signer_id: AccountId = match account_hex.parse() {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": format!("invalid account id: {}", e)}).to_string(),
    };

    let multisig_state_pda = compute_multisig_state_pda(&multisig_program_id, &create_key);
    let proposal_pda = compute_proposal_pda(&multisig_program_id, &create_key, proposal_index);

    let instruction = if is_approve {
        Instruction::Approve { proposal_index }
    } else {
        Instruction::Reject { proposal_index }
    };

    let account_ids = vec![multisig_state_pda, signer_id, proposal_pda];

    match submit_signed_multisig_tx(
        &wallet_core,
        multisig_program_id,
        account_ids,
        signer_id,
        instruction,
    ).await {
        Ok(tx_hash) => json!({
            "success": true,
            "tx_hash": tx_hash,
            "proposal_index": proposal_index,
            "action": if is_approve { "approved" } else { "rejected" },
        }).to_string(),
        Err(e) => json!({"success": false, "error": e}).to_string(),
    }
}

/// Execute a fully-approved proposal.
///
/// Args JSON:
/// ```json
/// {
///   "sequencer_url":       "http://127.0.0.1:3040",
///   "wallet_path":         "/path/to/wallet",
///   "multisig_program_id": "(64 hex chars)",
///   "account":             "<executor AccountId>",
///   "create_key":          "(64 hex chars)",
///   "proposal_index":      1
/// }
/// ```
pub fn execute(args: &str) -> String {
    let v = match parse_args(args) {
        Ok(v) => v,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return json!({"success": false, "error": format!("runtime error: {}", e)}).to_string(),
    };

    rt.block_on(async { execute_async(&v).await })
}

async fn execute_async(v: &Value) -> String {
    let sequencer_url = match get_str(v, "sequencer_url") {
        Ok(s) => s.to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let wallet_path = v["wallet_path"].as_str();
    let prog_id_hex = match get_str(v, "multisig_program_id") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let account_hex = match get_str(v, "account") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key_hex = match get_str(v, "create_key") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let proposal_index = match v["proposal_index"].as_u64() {
        Some(i) => i,
        None => return json!({"success": false, "error": "missing 'proposal_index'"}).to_string(),
    };

    let multisig_program_id = match parse_program_id_hex(prog_id_hex) {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key = match parse_hex32(create_key_hex, "create_key") {
        Ok(k) => k,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    std::env::set_var("NSSA_SEQUENCER_URL", &sequencer_url);

    let wallet_core = match load_wallet(wallet_path) {
        Ok(w) => w,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let signer_id: AccountId = match account_hex.parse() {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": format!("invalid account id: {}", e)}).to_string(),
    };

    let multisig_state_pda = compute_multisig_state_pda(&multisig_program_id, &create_key);
    let proposal_pda = compute_proposal_pda(&multisig_program_id, &create_key, proposal_index);

    let instruction = Instruction::Execute { proposal_index };

    let account_ids = vec![multisig_state_pda, signer_id, proposal_pda];

    match submit_signed_multisig_tx(
        &wallet_core,
        multisig_program_id,
        account_ids,
        signer_id,
        instruction,
    ).await {
        Ok(tx_hash) => json!({
            "success": true,
            "tx_hash": tx_hash,
            "proposal_index": proposal_index,
        }).to_string(),
        Err(e) => json!({"success": false, "error": e}).to_string(),
    }
}

/// List proposals for a multisig (reads PDAs for indices 1..transaction_index).
///
/// Args JSON:
/// ```json
/// {
///   "sequencer_url":       "http://127.0.0.1:3040",
///   "wallet_path":         "/path/to/wallet",
///   "multisig_program_id": "(64 hex chars)",
///   "create_key":          "(64 hex chars)"
/// }
/// ```
pub fn list_proposals(args: &str) -> String {
    let v = match parse_args(args) {
        Ok(v) => v,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return json!({"success": false, "error": format!("runtime error: {}", e)}).to_string(),
    };

    rt.block_on(async { list_proposals_async(&v).await })
}

async fn list_proposals_async(v: &Value) -> String {
    let sequencer_url = match get_str(v, "sequencer_url") {
        Ok(s) => s.to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let wallet_path = v["wallet_path"].as_str();
    let prog_id_hex = match get_str(v, "multisig_program_id") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key_hex = match get_str(v, "create_key") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let multisig_program_id = match parse_program_id_hex(prog_id_hex) {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key = match parse_hex32(create_key_hex, "create_key") {
        Ok(k) => k,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    std::env::set_var("NSSA_SEQUENCER_URL", &sequencer_url);

    let wallet_core = match load_wallet(wallet_path) {
        Ok(w) => w,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let multisig_state_pda = compute_multisig_state_pda(&multisig_program_id, &create_key);

    let state = match fetch_borsh_account::<MultisigState>(&wallet_core, multisig_state_pda).await {
        Ok(Some(s)) => s,
        Ok(None) => return json!({
            "success": true,
            "proposals": [],
            "note": "multisig state account not found"
        }).to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let mut proposals_json = Vec::new();

    for idx in 1..=state.transaction_index {
        let proposal_pda = compute_proposal_pda(&multisig_program_id, &create_key, idx);
        match fetch_borsh_account::<Proposal>(&wallet_core, proposal_pda).await {
            Ok(Some(p)) => {
                proposals_json.push(json!({
                    "index": p.index,
                    "proposer": bytes32_to_hex(&p.proposer),
                    "multisig_create_key": bytes32_to_hex(&p.multisig_create_key),
                    "target_program_id": program_id_to_hex(&p.target_program_id),
                    "target_account_count": p.target_account_count,
                    "approved_count": p.approved.len(),
                    "rejected_count": p.rejected.len(),
                    "status": status_str(&p.status),
                    "proposal_pda": proposal_pda.to_string(),
                }));
            }
            Ok(None) => {
                // Missing proposal — include stub
                proposals_json.push(json!({
                    "index": idx,
                    "status": "Missing",
                    "proposal_pda": proposal_pda.to_string(),
                }));
            }
            Err(_) => {
                // Skip unreadable proposals
            }
        }
    }

    json!({
        "success": true,
        "proposals": proposals_json,
        "transaction_index": state.transaction_index,
        "multisig_state_pda": multisig_state_pda.to_string(),
    }).to_string()
}

/// Get the state of a multisig.
///
/// Args JSON:
/// ```json
/// {
///   "sequencer_url":       "http://127.0.0.1:3040",
///   "wallet_path":         "/path/to/wallet",
///   "multisig_program_id": "(64 hex chars)",
///   "create_key":          "(64 hex chars)"
/// }
/// ```
pub fn get_state(args: &str) -> String {
    let v = match parse_args(args) {
        Ok(v) => v,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return json!({"success": false, "error": format!("runtime error: {}", e)}).to_string(),
    };

    rt.block_on(async { get_state_async(&v).await })
}

async fn get_state_async(v: &Value) -> String {
    let sequencer_url = match get_str(v, "sequencer_url") {
        Ok(s) => s.to_string(),
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let wallet_path = v["wallet_path"].as_str();
    let prog_id_hex = match get_str(v, "multisig_program_id") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key_hex = match get_str(v, "create_key") {
        Ok(s) => s,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let multisig_program_id = match parse_program_id_hex(prog_id_hex) {
        Ok(id) => id,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };
    let create_key = match parse_hex32(create_key_hex, "create_key") {
        Ok(k) => k,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    std::env::set_var("NSSA_SEQUENCER_URL", &sequencer_url);

    let wallet_core = match load_wallet(wallet_path) {
        Ok(w) => w,
        Err(e) => return json!({"success": false, "error": e}).to_string(),
    };

    let multisig_state_pda = compute_multisig_state_pda(&multisig_program_id, &create_key);

    match fetch_borsh_account::<MultisigState>(&wallet_core, multisig_state_pda).await {
        Ok(None) => json!({
            "success": false,
            "error": "multisig state account not found",
            "multisig_state_pda": multisig_state_pda.to_string(),
        }).to_string(),
        Ok(Some(state)) => {
            let members_hex: Vec<String> = state.members.iter()
                .map(|m| bytes32_to_hex(m))
                .collect();
            json!({
                "success": true,
                "state": {
                    "create_key": bytes32_to_hex(&state.create_key),
                    "threshold": state.threshold,
                    "member_count": state.member_count,
                    "members": members_hex,
                    "transaction_index": state.transaction_index,
                },
                "multisig_state_pda": multisig_state_pda.to_string(),
            }).to_string()
        }
        Err(e) => json!({"success": false, "error": e}).to_string(),
    }
}
