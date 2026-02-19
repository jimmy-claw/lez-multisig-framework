use clap::{CommandFactory, Parser, Subcommand};
use clap_complete::{Shell, generate};
use nssa::{
    AccountId, PublicTransaction,
    program::Program,
    public_transaction::{Message, WitnessSet},
};
use multisig_core::{Instruction, compute_multisig_state_pda};
use wallet::WalletCore;

/// LSSA Multisig CLI — M-of-N threshold governance for LEZ
#[derive(Parser)]
#[command(name = "multisig", version, about, long_about = None)]
#[command(propagate_version = true)]
struct Cli {
    /// Path to the multisig program binary
    #[arg(long, short = 'p', env = "MULTISIG_PROGRAM", default_value = "target/riscv32im-risc0-zkvm-elf/docker/multisig")]
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
        /// Member account IDs
        #[arg(long, short = 'm', num_args = 1..)]
        member: Vec<String>,
    },

    /// Execute a multisig transfer (requires M signer signatures)
    Execute {
        /// Recipient account ID
        #[arg(long)]
        to: String,
        /// Amount to transfer
        #[arg(long)]
        amount: u128,
        /// Signer account ID (your local key)
        #[arg(long)]
        signer: String,
    },

    /// Add a member to the multisig (requires M signatures)
    AddMember {
        /// New member account ID
        #[arg(long)]
        member: String,
    },

    /// Remove a member from the multisig (requires M signatures)
    RemoveMember {
        /// Member account ID to remove
        #[arg(long)]
        member: String,
    },

    /// Change the multisig threshold (requires M signatures)
    SetThreshold {
        /// New threshold value
        #[arg(long, short = 't')]
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
        .unwrap_or_else(|e| panic!("Failed to read program at {}: {}", path, e));
    let program = Program::new(bytecode).unwrap();
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
        _ => {}
    }

    let wallet_core = WalletCore::from_env().unwrap();
    let (_, program_id) = load_program(&cli.program);

    match cli.command {
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

        Commands::Execute { to, amount, signer } => {
            let signer_id: AccountId = signer.parse().unwrap();
            let to_id: AccountId = to.parse().unwrap();
            let multisig_state_id = compute_multisig_state_pda(&program_id);

            println!("💸 Executing multisig transfer");
            println!("   Amount: {} → {}", amount, to_id);
            println!("   Signer: {}", signer_id);

            let nonces = wallet_core.get_accounts_nonces(vec![signer_id.clone()]).await
                .expect("Failed to get nonces");
            let signing_key = wallet_core.storage().user_data
                .get_pub_account_signing_key(&signer_id)
                .expect("Signing key not found");

            let instruction = Instruction::Execute {
                recipient: to_id.clone(),
                amount,
            };

            let message = Message::try_new(
                program_id,
                vec![multisig_state_id, to_id],
                nonces,
                instruction,
            ).unwrap();
            let witness_set = WitnessSet::for_message(&message, &[signing_key]);
            let tx = PublicTransaction::new(message, witness_set);
            submit_and_confirm(&wallet_core, tx, "Multisig execute").await;
        }

        Commands::AddMember { member } => {
            let member_id: AccountId = member.parse().unwrap();
            let multisig_state_id = compute_multisig_state_pda(&program_id);

            println!("➕ Adding member: {}", member_id);

            let instruction = Instruction::AddMember {
                new_member: *member_id.value(),
            };

            let message = Message::try_new(
                program_id,
                vec![multisig_state_id],
                vec![],
                instruction,
            ).unwrap();
            let witness_set = WitnessSet::for_message(&message, &[] as &[&nssa::PrivateKey]);
            let tx = PublicTransaction::new(message, witness_set);
            submit_and_confirm(&wallet_core, tx, "Add member").await;
        }

        Commands::RemoveMember { member } => {
            let member_id: AccountId = member.parse().unwrap();
            let multisig_state_id = compute_multisig_state_pda(&program_id);

            println!("➖ Removing member: {}", member_id);

            let instruction = Instruction::RemoveMember {
                member_to_remove: *member_id.value(),
            };

            let message = Message::try_new(
                program_id,
                vec![multisig_state_id],
                vec![],
                instruction,
            ).unwrap();
            let witness_set = WitnessSet::for_message(&message, &[] as &[&nssa::PrivateKey]);
            let tx = PublicTransaction::new(message, witness_set);
            submit_and_confirm(&wallet_core, tx, "Remove member").await;
        }

        Commands::SetThreshold { threshold } => {
            let multisig_state_id = compute_multisig_state_pda(&program_id);

            println!("🔧 Setting threshold to {}", threshold);

            let instruction = Instruction::ChangeThreshold {
                new_threshold: threshold,
            };

            let message = Message::try_new(
                program_id,
                vec![multisig_state_id],
                vec![],
                instruction,
            ).unwrap();
            let witness_set = WitnessSet::for_message(&message, &[] as &[&nssa::PrivateKey]);
            let tx = PublicTransaction::new(message, witness_set);
            submit_and_confirm(&wallet_core, tx, "Set threshold").await;
        }

        Commands::Completions { .. } | Commands::Status => unreachable!(),
    }
}
