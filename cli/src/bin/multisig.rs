use clap::{CommandFactory, Parser, Subcommand};
use clap_complete::{Shell, generate};
use nssa::{
    AccountId, PublicKey, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use multisig_core::{Instruction, compute_multisig_state_pda};
use wallet::WalletCore;

mod proposal;
use proposal::Proposal;

/// LSSA Multisig CLI — M-of-N threshold governance for LEZ
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
    /// Create a new M-of-N multisig (submitted directly, no proposal needed)
    Create {
        /// Required signatures (M)
        #[arg(long, short = 't')]
        threshold: u8,
        /// Member account IDs (base58)
        #[arg(long, short = 'm', num_args = 1..)]
        member: Vec<String>,
    },

    /// Create a proposal for a multisig action (transfer, add/remove member, etc.)
    Propose {
        /// Output file for the proposal
        #[arg(long, short = 'o', default_value = "proposal.json")]
        output: String,

        /// Signer account IDs that will sign this proposal (base58, one per --signer)
        #[arg(long, short = 's', num_args = 1..)]
        signer: Vec<String>,

        #[command(subcommand)]
        action: ProposeAction,
    },

    /// Sign a proposal with your local key
    Sign {
        /// Path to the proposal file
        #[arg(long, short = 'f', default_value = "proposal.json")]
        file: String,

        /// Your account ID (base58)
        #[arg(long)]
        account: String,
    },

    /// Execute a signed proposal (submit to sequencer)
    Execute {
        /// Path to the signed proposal file
        #[arg(long, short = 'f', default_value = "proposal.json")]
        file: String,
    },

    /// Show proposal info
    Inspect {
        /// Path to the proposal file
        #[arg(long, short = 'f', default_value = "proposal.json")]
        file: String,
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

#[derive(Subcommand)]
enum ProposeAction {
    /// Transfer funds from the multisig
    Transfer {
        /// Recipient account ID
        #[arg(long)]
        to: String,
        /// Amount to transfer
        #[arg(long)]
        amount: u128,
    },

    /// Add a new member
    AddMember {
        /// New member account ID
        #[arg(long)]
        member: String,
    },

    /// Remove a member
    RemoveMember {
        /// Member account ID to remove
        #[arg(long)]
        member: String,
    },

    /// Change the threshold
    SetThreshold {
        /// New threshold value
        #[arg(long, short = 't')]
        threshold: u8,
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
            eprintln!("  The file exists but isn't a valid risc0 ELF binary.");
            eprintln!("  Rebuild with:  cargo risczero build --manifest-path methods/guest/Cargo.toml");
            std::process::exit(1);
        });
    let id = program.id();
    (program, id)
}

async fn submit_and_confirm(
    wallet_core: &WalletCore,
    tx: PublicTransaction,
    label: &str,
) {
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

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    // Handle commands that don't need wallet/program
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
                    let program_id = program.id();
                    let multisig_state_id = compute_multisig_state_pda(&program_id);
                    println!("   Program ID:     {:?}", program_id);
                    println!("   Multisig PDA:   {}", multisig_state_id);
                }
            } else {
                println!("   Program binary: not found (build with `cargo risczero build`)");
            }
            println!();
            println!("   (On-chain state query not yet implemented — needs sequencer query API)");
            return;
        }
        Commands::Inspect { file } => {
            let proposal = Proposal::load(file).unwrap_or_else(|e| {
                eprintln!("Error loading proposal '{}': {}", file, e);
                std::process::exit(1);
            });

            println!("📋 Proposal: {}", proposal.description);
            println!("   Signatures: {}", proposal.signature_count());
            for (i, sig) in proposal.signatures.iter().enumerate() {
                println!("   [{}] {}", i, sig.account_id);
            }

            // Verify signatures
            match proposal.verify_signatures() {
                Ok(()) => println!("   ✅ All signatures valid"),
                Err(e) => println!("   ❌ {}", e),
            }
            return;
        }
        _ => {}
    }

    let wallet_core = WalletCore::from_env().unwrap();
    let (_, program_id) = load_program(&cli.program);

    match cli.command {
        // ── Create (direct submit, no proposal needed) ──────────────────
        Commands::Create { threshold, member } => {
            let members: Vec<AccountId> = member.iter()
                .map(|s| s.parse().expect("Invalid member ID"))
                .collect();

            if (threshold as usize) > members.len() {
                eprintln!("Error: threshold ({}) > members ({})", threshold, members.len());
                std::process::exit(1);
            }

            let multisig_state_id = compute_multisig_state_pda(&program_id);

            println!("🔐 Creating {}-of-{} multisig", threshold, members.len());
            println!("   State PDA:  {}", multisig_state_id);
            for (i, m) in members.iter().enumerate() {
                println!("   Member [{}]: {}", i, m);
            }

            let instruction = Instruction::CreateMultisig {
                threshold,
                members: members.iter().map(|id| *id.value()).collect(),
            };

            let message = Message::try_new(
                program_id,
                vec![multisig_state_id],
                vec![],
                instruction,
            ).unwrap();
            let witness_set = WitnessSet::for_message(&message, &[] as &[&nssa::PrivateKey]);
            let tx = PublicTransaction::new(message, witness_set);
            submit_and_confirm(&wallet_core, tx, "Create multisig").await;
        }

        // ── Propose (create proposal file for offline signing) ──────────
        Commands::Propose { output, signer, action } => {
            let multisig_state_id = compute_multisig_state_pda(&program_id);

            // Parse signer account IDs
            let signer_ids: Vec<AccountId> = signer.iter()
                .map(|s| s.parse().expect("Invalid signer account ID"))
                .collect();

            if signer_ids.is_empty() {
                eprintln!("Error: at least one --signer required");
                std::process::exit(1);
            }

            // Build the instruction and description
            let (instruction, description) = match &action {
                ProposeAction::Transfer { to, amount } => {
                    let to_id: AccountId = to.parse().expect("Invalid recipient ID");
                    (
                        Instruction::Execute { recipient: to_id, amount: *amount },
                        format!("Transfer {} to {}", amount, to),
                    )
                }
                ProposeAction::AddMember { member } => {
                    let member_id: AccountId = member.parse().expect("Invalid member ID");
                    (
                        Instruction::AddMember { new_member: *member_id.value() },
                        format!("Add member {}", member),
                    )
                }
                ProposeAction::RemoveMember { member } => {
                    let member_id: AccountId = member.parse().expect("Invalid member ID");
                    (
                        Instruction::RemoveMember { member_to_remove: *member_id.value() },
                        format!("Remove member {}", member),
                    )
                }
                ProposeAction::SetThreshold { threshold } => {
                    (
                        Instruction::ChangeThreshold { new_threshold: *threshold },
                        format!("Change threshold to {}", threshold),
                    )
                }
            };

            // Build account list:
            // [0] = multisig state PDA
            // [1..] = signer accounts (so they get is_authorized = true)
            let mut account_ids = vec![multisig_state_id];
            account_ids.extend(signer_ids.iter().cloned());

            // Fetch nonces for signer accounts
            let nonces = wallet_core
                .get_accounts_nonces(signer_ids.clone())
                .await
                .expect("Failed to get nonces from sequencer");

            let message = Message::try_new(
                program_id,
                account_ids,
                nonces,
                instruction,
            ).unwrap();

            let proposal = Proposal::new(&message, description.clone());
            proposal.save(&output).unwrap_or_else(|e| {
                eprintln!("Error saving proposal: {}", e);
                std::process::exit(1);
            });

            println!("📝 Proposal created: {}", description);
            println!("   Saved to: {}", output);
            println!("   Signers needed: {}", signer_ids.len());
            for (i, s) in signer_ids.iter().enumerate() {
                println!("   [{}] {}", i, s);
            }
            println!();
            println!("   Next: each signer runs:");
            println!("     multisig sign --file {} --account <THEIR_ACCOUNT_ID>", output);
        }

        // ── Sign (add your signature to a proposal) ─────────────────────
        Commands::Sign { file, account } => {
            let account_id: AccountId = account.parse().expect("Invalid account ID");

            let mut proposal = Proposal::load(&file).unwrap_or_else(|e| {
                eprintln!("Error loading proposal '{}': {}", file, e);
                std::process::exit(1);
            });

            // Get signing key from wallet
            let signing_key = wallet_core
                .storage()
                .user_data
                .get_pub_account_signing_key(account_id)
                .expect("Signing key not found for this account — is it in your wallet?");

            // Sign the message
            let message = proposal.message();
            let witness = WitnessSet::for_message(&message, &[signing_key]);
            let (signature, public_key) = witness
                .into_raw_parts()
                .into_iter()
                .next()
                .expect("WitnessSet should contain exactly one signature");

            // Verify the public key maps to the claimed account ID
            let derived_account_id = AccountId::from(&public_key);
            if derived_account_id != account_id {
                eprintln!("Error: signing key for {} produces account ID {}", account_id, derived_account_id);
                eprintln!("  The account ID doesn't match. Wrong key?");
                std::process::exit(1);
            }

            proposal.add_signature(&account_id, &public_key, &signature);
            proposal.save(&file).unwrap_or_else(|e| {
                eprintln!("Error saving proposal: {}", e);
                std::process::exit(1);
            });

            println!("✍️  Signed proposal: {}", proposal.description);
            println!("   Signer: {}", account_id);
            println!("   Total signatures: {}", proposal.signature_count());
            println!("   Saved to: {}", file);
        }

        // ── Execute (submit a fully-signed proposal) ────────────────────
        Commands::Execute { file } => {
            let proposal = Proposal::load(&file).unwrap_or_else(|e| {
                eprintln!("Error loading proposal '{}': {}", file, e);
                std::process::exit(1);
            });

            if proposal.signature_count() == 0 {
                eprintln!("Error: proposal has no signatures");
                std::process::exit(1);
            }

            // Verify all signatures
            proposal.verify_signatures().unwrap_or_else(|e| {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            });

            println!("📤 Executing proposal: {}", proposal.description);
            println!("   Signatures: {}", proposal.signature_count());

            // Reconstruct the message and witness set
            let message = proposal.message();
            let witness_set = proposal.witness_set();

            let tx = PublicTransaction::new(message, witness_set);
            submit_and_confirm(&wallet_core, tx, "Multisig proposal").await;
        }

        Commands::Completions { .. } | Commands::Status | Commands::Inspect { .. } => unreachable!(),
    }
}
