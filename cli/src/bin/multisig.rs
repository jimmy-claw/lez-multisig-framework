use clap::{CommandFactory, Parser, Subcommand};
use clap_complete::{Shell, generate};
use nssa::{
    AccountId, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use multisig_core::{
    Instruction,
    compute_multisig_state_pda,
    compute_proposal_pda,
};
use wallet::WalletCore;

/// LEZ Multisig CLI — M-of-N threshold governance for LEZ
///
/// Squads-style on-chain proposal flow:
///   propose → approve (by M members) → execute
#[derive(Parser)]
#[command(name = "multisig", version, about, long_about = None)]
#[command(propagate_version = true)]
struct Cli {
    /// Path to the multisig program binary
    #[arg(long, short = 'p', env = "MULTISIG_PROGRAM", default_value = "target/riscv32im-risc0-zkvm-elf/docker/multisig.bin")]
    program: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a new M-of-N multisig
    Create {
        /// Required signatures (M)
        #[arg(long, short = 't')]
        threshold: u8,
        /// Member account IDs (base58)
        #[arg(long, short = 'm', num_args = 1..)]
        member: Vec<String>,
        /// Optional create key (base58). If omitted, a random one is generated.
        #[arg(long)]
        create_key: Option<String>,
    },

    /// Create a proposal (raw instruction data)
    Propose {
        /// Multisig create_key (base58) to identify which multisig
        #[arg(long)]
        multisig: String,
        /// Your account ID (base58, must be a member)
        #[arg(long)]
        account: String,
        /// Target program ID (base58)
        #[arg(long)]
        target_program: String,
        /// Serialized instruction data for the target program (hex-encoded u32 words, e.g. "01000000 02000000")
        #[arg(long, num_args = 0..)]
        instruction_data: Vec<String>,
        /// Number of target accounts expected at execute time
        #[arg(long, default_value = "0")]
        target_account_count: u8,
        /// PDA seeds (hex-encoded 32-byte values)
        #[arg(long, num_args = 0..)]
        pda_seed: Vec<String>,
        /// Which target account indices (0-based) get is_authorized=true
        #[arg(long, num_args = 0..)]
        authorized_index: Vec<u8>,
        /// Proposal index hint (used to compute proposal PDA — set to expected next index)
        #[arg(long)]
        proposal_index: u64,
    },

    /// Approve a proposal
    Approve {
        /// Multisig create_key (base58)
        #[arg(long)]
        multisig: String,
        /// Proposal index
        #[arg(long, short = 'i')]
        index: u64,
        /// Your account ID (base58, must be a member)
        #[arg(long)]
        account: String,
    },

    /// Reject a proposal
    Reject {
        /// Multisig create_key (base58)
        #[arg(long)]
        multisig: String,
        /// Proposal index
        #[arg(long, short = 'i')]
        index: u64,
        /// Your account ID (base58, must be a member)
        #[arg(long)]
        account: String,
    },

    /// Execute a fully-approved proposal
    Execute {
        /// Multisig create_key (base58)
        #[arg(long)]
        multisig: String,
        /// Proposal index
        #[arg(long, short = 'i')]
        index: u64,
        /// Your account ID (base58, must be a member)
        #[arg(long)]
        account: String,
    },

    /// Propose adding a new member to the multisig
    AddMember {
        /// Multisig create_key (base58)
        #[arg(long)]
        multisig: String,
        /// Your account ID (base58, must be a member)
        #[arg(long)]
        account: String,
        /// New member account ID (base58)
        #[arg(long)]
        member: String,
    },

    /// Propose removing a member from the multisig
    RemoveMember {
        /// Multisig create_key (base58)
        #[arg(long)]
        multisig: String,
        /// Your account ID (base58, must be a member)
        #[arg(long)]
        account: String,
        /// Member to remove (base58)
        #[arg(long)]
        member: String,
    },

    /// Propose changing the approval threshold
    ChangeThreshold {
        /// Multisig create_key (base58)
        #[arg(long)]
        multisig: String,
        /// Your account ID (base58, must be a member)
        #[arg(long)]
        account: String,
        /// New threshold value
        #[arg(long)]
        threshold: u8,
    },

    /// Show multisig status
    Status,

    /// Generate shell completions
    Completions {
        /// Shell to generate for
        #[arg(value_enum)]
        shell: Shell,
    },
}

fn load_program(path: &str) -> (Program, nssa::ProgramId) {
    let bytecode = std::fs::read(path)
        .unwrap_or_else(|e| {
            eprintln!("Error: Cannot read program binary at '{}': {}", path, e);
            eprintln!("  Build it first:  cargo risczero build --manifest-path methods/guest/Cargo.toml");
            eprintln!("  Or set path:     --program <path> or MULTISIG_PROGRAM=<path>");
            std::process::exit(1);
        });
    let program = Program::new(bytecode)
        .unwrap_or_else(|e| {
            eprintln!("Error: Invalid program bytecode at '{}': {:?}", path, e);
            std::process::exit(1);
        });
    let id = program.id();
    (program, id)
}

async fn submit_and_confirm(wallet_core: &WalletCore, tx: PublicTransaction, label: &str) {
    let response = wallet_core
        .sequencer_client
        .send_tx_public(tx)
        .await
        .unwrap();

    println!("📤 {} submitted", label);
    println!("   tx_hash: {}", response.tx_hash);
    println!("   Waiting for confirmation...");

    let poller = wallet::poller::TxPoller::new(
        wallet_core.config().clone(),
        wallet_core.sequencer_client.clone(),
    );

    match poller.poll_tx(response.tx_hash).await {
        Ok(_) => println!("✅ Confirmed!"),
        Err(e) => {
            eprintln!("❌ Not confirmed: {e:#}");
            std::process::exit(1);
        }
    }
}

/// Build and submit a single-signer transaction.
/// `account_ids` is the full ordered account list for the instruction.
/// `signer_id` is the one signing account (nonce provided only for it).
async fn submit_signed_tx(
    wallet_core: &WalletCore,
    program_id: nssa::ProgramId,
    account_ids: Vec<AccountId>,
    signer_id: AccountId,
    instruction: Instruction,
    label: &str,
) {
    let nonces = wallet_core
        .get_accounts_nonces(vec![signer_id])
        .await
        .expect("Failed to get nonces");

    let signing_key = wallet_core
        .storage()
        .user_data
        .get_pub_account_signing_key(signer_id)
        .expect("Signing key not found — is this account in your wallet?");

    let message = Message::try_new(
        program_id,
        account_ids,
        nonces,
        instruction,
    ).unwrap();

    let witness_set = WitnessSet::for_message(&message, &[signing_key]);
    let tx = PublicTransaction::new(message, witness_set);
    submit_and_confirm(wallet_core, tx, label).await;
}

/// Parse a hex string into a 32-byte array.
fn parse_hex32(s: &str) -> [u8; 32] {
    let bytes = hex::decode(s).expect("Invalid hex value (expected 64 hex chars for 32 bytes)");
    if bytes.len() != 32 {
        eprintln!("Error: expected 32 bytes (64 hex chars), got {}", bytes.len());
        std::process::exit(1);
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    arr
}

/// Parse create_key from base58 AccountId string to [u8; 32].
fn parse_create_key(s: &str) -> [u8; 32] {
    let id: AccountId = s.parse().expect("Invalid multisig create_key (base58)");
    *id.value()
}

/// Parse a ProgramId ([u32; 8]) from a 64-char hex string (32 bytes, interpreted as 8 little-endian u32s).
fn parse_program_id(s: &str) -> nssa::ProgramId {
    let bytes = hex::decode(s).unwrap_or_else(|_| {
        eprintln!("Error: invalid hex for program ID (expected 64 hex chars): {}", s);
        std::process::exit(1);
    });
    if bytes.len() != 32 {
        eprintln!("Error: program ID must be 32 bytes (64 hex chars), got {}", bytes.len());
        std::process::exit(1);
    }
    let mut id = [0u32; 8];
    for i in 0..8 {
        id[i] = u32::from_le_bytes([bytes[i*4], bytes[i*4+1], bytes[i*4+2], bytes[i*4+3]]);
    }
    id
}

/// Parse hex-encoded u32 words into Vec<u32>.
/// Each word is a hex string like "01000000" (little-endian u32) or a plain u32 decimal.
fn parse_instruction_data(args: &[String]) -> Vec<u32> {
    args.iter().map(|s| {
        // Try hex first
        if let Ok(bytes) = hex::decode(s) {
            if bytes.len() == 4 {
                return u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
            }
        }
        // Fall back to decimal
        s.parse::<u32>().unwrap_or_else(|_| {
            eprintln!("Error: instruction data word '{}' is neither valid 4-byte hex nor decimal u32", s);
            std::process::exit(1);
        })
    }).collect()
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    // Commands that don't need wallet/program
    match &cli.command {
        Commands::Completions { shell } => {
            generate(*shell, &mut Cli::command(), "multisig", &mut std::io::stdout());
            return;
        }
        Commands::Status => {
            println!("📊 Multisig Status");
            println!("   Program path:   {}", cli.program);
            if let Ok(bytecode) = std::fs::read(&cli.program) {
                if let Ok(program) = Program::new(bytecode) {
                    println!("   Program ID:     {:?}", program.id());
                }
            } else {
                println!("   Program binary: not found");
            }
            println!("   Use --create-key with 'create' or --multisig with other commands");
            return;
        }
        _ => {}
    }

    let wallet_core = WalletCore::from_env().unwrap();
    let (_, program_id) = load_program(&cli.program);

    match cli.command {
        // ── Create ──────────────────────────────────────────────────────
        //
        // Account layout: [state_pda, member1, member2, ..., memberN]
        // No signer required — anyone can create.
        Commands::Create { threshold, member, create_key } => {
            let members: Vec<AccountId> = member.iter()
                .map(|s| s.parse().expect("Invalid member ID"))
                .collect();

            if (threshold as usize) > members.len() {
                eprintln!("Error: threshold ({}) > members ({})", threshold, members.len());
                std::process::exit(1);
            }

            // Generate or use provided create_key
            let ck: [u8; 32] = if let Some(ref key_str) = create_key {
                parse_create_key(key_str)
            } else {
                let random_key = nssa::PrivateKey::new_os_random();
                let pk = nssa::PublicKey::new_from_private_key(&random_key);
                *AccountId::from(&pk).value()
            };

            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);

            println!("🔐 Creating {}-of-{} multisig", threshold, members.len());
            println!("   Create key: {}", AccountId::new(ck));
            println!("   State PDA:  {}", multisig_state_id);

            let instruction = Instruction::CreateMultisig {
                create_key: ck,
                threshold,
                members: members.iter().map(|id| *id.value()).collect(),
            };

            // Account list: [state_pda, member1, member2, ..., memberN]
            let mut account_ids = vec![multisig_state_id];
            account_ids.extend(members.iter().copied());

            let message = Message::try_new(
                program_id,
                account_ids,
                vec![],
                instruction,
            ).unwrap();
            let witness_set = WitnessSet::for_message(&message, &[] as &[&nssa::PrivateKey]);
            let tx = PublicTransaction::new(message, witness_set);
            submit_and_confirm(&wallet_core, tx, "Create multisig").await;

            println!("\n💡 Save this create key to interact with the multisig:");
            println!("   {}", AccountId::new(ck));
        }

        // ── Propose ─────────────────────────────────────────────────────
        //
        // Account layout: [state_pda, proposer, proposal_pda]
        // Proposer is the signer.
        Commands::Propose {
            multisig,
            account,
            target_program,
            instruction_data,
            target_account_count,
            pda_seed,
            authorized_index,
            proposal_index,
        } => {
            let ck = parse_create_key(&multisig);
            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);
            let account_id: AccountId = account.parse().expect("Invalid account ID");
            let proposal_pda = compute_proposal_pda(&program_id, &ck, proposal_index);

            let target_program_id: nssa::ProgramId = parse_program_id(&target_program);

            let target_instruction_data = parse_instruction_data(&instruction_data);

            let pda_seeds: Vec<[u8; 32]> = pda_seed.iter()
                .map(|s| parse_hex32(s))
                .collect();

            println!("📝 Creating proposal #{}...", proposal_index);
            println!("   State PDA:    {}", multisig_state_id);
            println!("   Proposer:     {}", account_id);
            println!("   Proposal PDA: {}", proposal_pda);

            let instruction = Instruction::Propose {
                target_program_id,
                target_instruction_data,
                target_account_count,
                pda_seeds,
                authorized_indices: authorized_index,
            };

            submit_signed_tx(
                &wallet_core, program_id,
                vec![multisig_state_id, account_id, proposal_pda],
                account_id,
                instruction,
                "Propose",
            ).await;
        }

        // ── Approve ─────────────────────────────────────────────────────
        //
        // Account layout: [state_pda, approver, proposal_pda]
        // Approver is the signer.
        Commands::Approve { multisig, index, account } => {
            let ck = parse_create_key(&multisig);
            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);
            let account_id: AccountId = account.parse().expect("Invalid account ID");
            let proposal_pda = compute_proposal_pda(&program_id, &ck, index);

            println!("👍 Approving proposal #{}...", index);
            println!("   State PDA:    {}", multisig_state_id);
            println!("   Approver:     {}", account_id);
            println!("   Proposal PDA: {}", proposal_pda);

            submit_signed_tx(
                &wallet_core, program_id,
                vec![multisig_state_id, account_id, proposal_pda],
                account_id,
                Instruction::Approve { proposal_index: index },
                "Approve",
            ).await;
        }

        // ── Reject ──────────────────────────────────────────────────────
        //
        // Account layout: [state_pda, rejector, proposal_pda]
        // Rejector is the signer.
        Commands::Reject { multisig, index, account } => {
            let ck = parse_create_key(&multisig);
            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);
            let account_id: AccountId = account.parse().expect("Invalid account ID");
            let proposal_pda = compute_proposal_pda(&program_id, &ck, index);

            println!("👎 Rejecting proposal #{}...", index);
            println!("   State PDA:    {}", multisig_state_id);
            println!("   Rejector:     {}", account_id);
            println!("   Proposal PDA: {}", proposal_pda);

            submit_signed_tx(
                &wallet_core, program_id,
                vec![multisig_state_id, account_id, proposal_pda],
                account_id,
                Instruction::Reject { proposal_index: index },
                "Reject",
            ).await;
        }

        // ── Execute ─────────────────────────────────────────────────────
        //
        // Account layout: [state_pda, executor, proposal_pda]
        // Executor is the signer. Target accounts are handled by ChainedCall
        // inside the program itself — no extra accounts needed in the CLI.
        Commands::Execute { multisig, index, account } => {
            let ck = parse_create_key(&multisig);
            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);
            let account_id: AccountId = account.parse().expect("Invalid account ID");
            let proposal_pda = compute_proposal_pda(&program_id, &ck, index);

            println!("⚡ Executing proposal #{}...", index);
            println!("   State PDA:    {}", multisig_state_id);
            println!("   Executor:     {}", account_id);
            println!("   Proposal PDA: {}", proposal_pda);

            submit_signed_tx(
                &wallet_core, program_id,
                vec![multisig_state_id, account_id, proposal_pda],
                account_id,
                Instruction::Execute { proposal_index: index },
                "Execute",
            ).await;
        }

        // ── Add Member ─────────────────────────────────────────────────
        Commands::AddMember { multisig, account, member } => {
            let ck = parse_create_key(&multisig);
            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);
            let account_id: AccountId = account.parse().expect("Invalid account ID");
            let new_member_id: AccountId = member.parse().expect("Invalid member ID");

            // Read current state to get next proposal index
            let state = wallet_core
                .sequencer_client
                .get_account(multisig_state_id)
                .await
                .expect("Failed to get multisig state");
            let state_data: Vec<u8> = state.account.data.into();
            let ms_state: multisig_core::MultisigState = borsh::from_slice(&state_data)
                .expect("Failed to deserialize multisig state");
            let proposal_index = ms_state.transaction_index + 1;
            let proposal_pda = compute_proposal_pda(&program_id, &ck, proposal_index);

            println!("➕ Proposing add member...");
            println!("   New member:   {}", new_member_id);
            println!("   Proposal #{}  PDA: {}", proposal_index, proposal_pda);

            submit_signed_tx(
                &wallet_core, program_id,
                vec![multisig_state_id, account_id, proposal_pda],
                account_id,
                Instruction::ProposeAddMember { new_member: *new_member_id.value() },
                "ProposeAddMember",
            ).await;
        }

        // ── Remove Member ───────────────────────────────────────────────
        Commands::RemoveMember { multisig, account, member } => {
            let ck = parse_create_key(&multisig);
            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);
            let account_id: AccountId = account.parse().expect("Invalid account ID");
            let member_id: AccountId = member.parse().expect("Invalid member ID");

            let state = wallet_core
                .sequencer_client
                .get_account(multisig_state_id)
                .await
                .expect("Failed to get multisig state");
            let state_data: Vec<u8> = state.account.data.into();
            let ms_state: multisig_core::MultisigState = borsh::from_slice(&state_data)
                .expect("Failed to deserialize multisig state");
            let proposal_index = ms_state.transaction_index + 1;
            let proposal_pda = compute_proposal_pda(&program_id, &ck, proposal_index);

            println!("➖ Proposing remove member...");
            println!("   Member:       {}", member_id);
            println!("   Proposal #{}  PDA: {}", proposal_index, proposal_pda);

            submit_signed_tx(
                &wallet_core, program_id,
                vec![multisig_state_id, account_id, proposal_pda],
                account_id,
                Instruction::ProposeRemoveMember { member: *member_id.value() },
                "ProposeRemoveMember",
            ).await;
        }

        // ── Change Threshold ────────────────────────────────────────────
        Commands::ChangeThreshold { multisig, account, threshold } => {
            let ck = parse_create_key(&multisig);
            let multisig_state_id = compute_multisig_state_pda(&program_id, &ck);
            let account_id: AccountId = account.parse().expect("Invalid account ID");

            let state = wallet_core
                .sequencer_client
                .get_account(multisig_state_id)
                .await
                .expect("Failed to get multisig state");
            let state_data: Vec<u8> = state.account.data.into();
            let ms_state: multisig_core::MultisigState = borsh::from_slice(&state_data)
                .expect("Failed to deserialize multisig state");
            let proposal_index = ms_state.transaction_index + 1;
            let proposal_pda = compute_proposal_pda(&program_id, &ck, proposal_index);

            println!("🔧 Proposing change threshold to {}...", threshold);
            println!("   Proposal #{}  PDA: {}", proposal_index, proposal_pda);

            submit_signed_tx(
                &wallet_core, program_id,
                vec![multisig_state_id, account_id, proposal_pda],
                account_id,
                Instruction::ProposeChangeThreshold { new_threshold: threshold },
                "ProposeChangeThreshold",
            ).await;
        }

        Commands::Completions { .. } | Commands::Status => unreachable!(),
    }
}
