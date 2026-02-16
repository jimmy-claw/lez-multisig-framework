// Multisig CLI commands for LEZ Wallet
// 
// Usage:
//   lez-wallet multisig create --threshold 2 --member <pk1> --member <pk2> --member <pk3>
//   lez-wallet multisig info --account <multisig_id>
//   lez-wallet multisig propose --multisig <id> --to <recipient> --amount 100
//   lez-wallet multisig sign --proposal <file> --output <signed_file>
//   lez-wallet multisig execute --proposal <file>
//   lez-wallet multisig add-member --multisig <id> --member <new_pk>
//   lez-wallet multisig remove-member --multisig <id> --member <pk>
//   lez-wallet multisig change-threshold --multisig <id> --threshold 3

use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};

#[derive(Parser)]
#[command(name = "multisig")]
#[command(about = "M-of-N Multisig Treasury Management")]
pub enum MultisigCommand {
    /// Create a new multisig with M-of-N threshold
    Create {
        /// Required signatures for execution (M)
        #[arg(long)]
        threshold: u8,
        
        /// Member public keys (can be specified multiple times)
        #[arg(long)]
        member: Vec<String>,
        
        /// Output file for multisig info
        #[arg(long)]
        output: Option<String>,
    },
    
    /// View multisig information
    Info {
        /// Multisig account ID
        #[arg(long)]
        account: String,
    },
    
    /// Propose a transaction
    Propose {
        /// Multisig account ID
        #[arg(long)]
        multisig: String,
        
        /// Recipient account ID
        #[arg(long)]
        to: String,
        
        /// Amount to transfer
        #[arg(long)]
        amount: u128,
        
        /// Output file for proposal
        #[arg(long)]
        output: String,
    },
    
    /// Sign a proposal
    Sign {
        /// Input proposal file
        #[arg(long)]
        proposal: String,
        
        /// Output file for signed proposal
        #[arg(long)]
        output: String,
    },
    
    /// Execute a proposal (collects signatures and submits)
    Execute {
        /// Proposal file (can specify multiple times for multiple signers)
        #[arg(long)]
        proposal: Vec<String>,
    },
    
    /// Add a new member
    AddMember {
        /// Multisig account ID
        #[arg(long)]
        multisig: String,
        
        /// New member's public key
        #[arg(long)]
        member: String,
    },
    
    /// Remove a member
    RemoveMember {
        /// Multisig account ID
        #[arg(long)]
        multisig: String,
        
        /// Member's public key to remove
        #[arg(long)]
        member: String,
    },
    
    /// Change the threshold
    ChangeThreshold {
        /// Multisig account ID
        #[arg(long)]
        multisig: String,
        
        /// New threshold value
        #[arg(long)]
        threshold: u8,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultisigInfo {
    pub account_id: String,
    pub threshold: u8,
    pub member_count: u8,
    pub members: Vec<String>,
    pub nonce: u64,
    pub balance: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Proposal {
    pub multisig_id: String,
    pub recipient: String,
    pub amount: u128,
    pub nonce: u64,
    pub signatures: Vec<String>,
}

impl MultisigCommand {
    pub async fn execute(&self, client: &WalletClient) -> Result<(), Box<dyn std::error::Error>> {
        match self {
            MultisigCommand::Create { threshold, member, output } => {
                Self::cmd_create(client, *threshold, member, output.as_deref()).await
            }
            MultisigCommand::Info { account } => {
                Self::cmd_info(client, account).await
            }
            MultisigCommand::Propose { multisig, to, amount, output } => {
                Self::cmd_propose(client, multisig, to, *amount, output).await
            }
            MultisigCommand::Sign { proposal, output } => {
                Self::cmd_sign(client, proposal, output).await
            }
            MultisigCommand::Execute { proposal } => {
                Self::cmd_execute(client, proposal).await
            }
            MultisigCommand::AddMember { multisig, member } => {
                Self::cmd_add_member(client, multisig, member).await
            }
            MultisigCommand::RemoveMember { multisig, member } => {
                Self::cmd_remove_member(client, multisig, member).await
            }
            MultisigCommand::ChangeThreshold { multisig, threshold } => {
                Self::cmd_change_threshold(client, multisig, *threshold).await
            }
        }
    }
    
    // Implementation methods...
}

impl MultisigInfo {
    pub fn from_account_data(data: &[u8]) -> Result<Self, Box<dyn std::error::Error>> {
        let state = treasury_core::MultisigState::try_from_slice(data)?;
        Ok(MultisigInfo {
            account_id: String::new(), // Would be set by caller
            threshold: state.threshold,
            member_count: state.member_count,
            members: state.members.iter().map(|pk| hex::encode(pk)).collect(),
            nonce: state.nonce,
            balance: 0, // Would get from account balance
        })
    }
}
