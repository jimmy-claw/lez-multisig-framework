//! Offline proposal and signing for M-of-N multisig transactions.
//!
//! Flow:
//! 1. `multisig propose` — creates a Proposal JSON file with transaction details
//! 2. `multisig sign` — each signer loads the proposal, signs it, appends their signature
//! 3. `multisig execute` — loads the signed proposal, builds the on-chain transaction, submits

use borsh::{BorshDeserialize, BorshSerialize};
use nssa::{
    AccountId, PublicKey, Signature,
    public_transaction::Message,
};
use serde::{Deserialize, Serialize};

/// A multisig proposal that can be shared between signers for offline signing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Proposal {
    /// Human-readable description
    pub description: String,
    /// The serialized Message bytes (borsh-encoded)
    /// This is what signers actually sign.
    #[serde(with = "hex_bytes")]
    pub message_bytes: Vec<u8>,
    /// Collected signatures so far
    pub signatures: Vec<ProposalSignature>,
}

/// A signature on a proposal, with the signer's public key and account ID.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposalSignature {
    /// Signer's account ID (base58)
    pub account_id: String,
    /// Signer's public key (hex)
    pub public_key: String,
    /// Schnorr signature over the message bytes (hex)
    pub signature: String,
}

impl Proposal {
    /// Create a new proposal from a Message.
    pub fn new(message: &Message, description: String) -> Self {
        let message_bytes = borsh::to_vec(message).expect("Message serialization should not fail");
        Self {
            description,
            message_bytes,
            signatures: Vec::new(),
        }
    }

    /// Deserialize the contained Message.
    pub fn message(&self) -> Message {
        Message::deserialize(&mut &self.message_bytes[..])
            .expect("Proposal contains invalid message bytes")
    }

    /// Add a signature to the proposal.
    pub fn add_signature(
        &mut self,
        account_id: &AccountId,
        public_key: &PublicKey,
        signature: &Signature,
    ) {
        // Check for duplicate signer
        let account_str = account_id.to_string();
        if self.signatures.iter().any(|s| s.account_id == account_str) {
            panic!("Account {} has already signed this proposal", account_str);
        }

        self.signatures.push(ProposalSignature {
            account_id: account_str,
            public_key: hex::encode(public_key.value()),
            signature: hex::encode(signature.value),
        });
    }

    /// Get the number of signatures collected.
    pub fn signature_count(&self) -> usize {
        self.signatures.len()
    }

    /// Verify all collected signatures against the message.
    pub fn verify_signatures(&self) -> Result<(), String> {
        let message_bytes = &self.message_bytes;
        // WitnessSet signs message.to_bytes(), not the borsh-serialized message
        let message = self.message();
        let sign_bytes = message.to_bytes();

        for (i, sig) in self.signatures.iter().enumerate() {
            let pk_bytes: [u8; 32] = hex::decode(&sig.public_key)
                .map_err(|e| format!("Signature {}: invalid public key hex: {}", i, e))?
                .try_into()
                .map_err(|_| format!("Signature {}: public key must be 32 bytes", i))?;

            let sig_bytes: [u8; 64] = hex::decode(&sig.signature)
                .map_err(|e| format!("Signature {}: invalid signature hex: {}", i, e))?
                .try_into()
                .map_err(|_| format!("Signature {}: signature must be 64 bytes", i))?;

            let public_key = PublicKey::try_new(pk_bytes)
                .map_err(|e| format!("Signature {}: invalid public key: {:?}", i, e))?;
            let signature = Signature { value: sig_bytes };

            if !signature.is_valid_for(&sign_bytes, &public_key) {
                return Err(format!(
                    "Signature {} from {} is invalid",
                    i, sig.account_id
                ));
            }
        }

        Ok(())
    }

    /// Build the signer account IDs list (for the Message account_ids).
    pub fn signer_account_ids(&self) -> Vec<AccountId> {
        self.signatures
            .iter()
            .map(|s| s.account_id.parse().expect("Invalid account ID in proposal"))
            .collect()
    }

    /// Build a WitnessSet from the collected signatures.
    pub fn witness_set(&self) -> nssa::public_transaction::WitnessSet {
        let pairs: Vec<(Signature, PublicKey)> = self
            .signatures
            .iter()
            .map(|s| {
                let pk_bytes: [u8; 32] = hex::decode(&s.public_key)
                    .expect("Invalid public key hex")
                    .try_into()
                    .expect("Public key must be 32 bytes");
                let sig_bytes: [u8; 64] = hex::decode(&s.signature)
                    .expect("Invalid signature hex")
                    .try_into()
                    .expect("Signature must be 64 bytes");

                (
                    Signature { value: sig_bytes },
                    PublicKey::try_new(pk_bytes).expect("Invalid public key"),
                )
            })
            .collect();

        nssa::public_transaction::WitnessSet::from_raw_parts(pairs)
    }

    /// Save proposal to a JSON file.
    pub fn save(&self, path: &str) -> std::io::Result<()> {
        let json = serde_json::to_string_pretty(self).expect("Proposal serialization failed");
        std::fs::write(path, json)
    }

    /// Load proposal from a JSON file.
    pub fn load(path: &str) -> std::io::Result<Self> {
        let json = std::fs::read_to_string(path)?;
        let proposal: Self = serde_json::from_str(&json)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        Ok(proposal)
    }
}

/// Helper module for hex-encoding Vec<u8> in serde JSON.
mod hex_bytes {
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(bytes: &Vec<u8>, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&hex::encode(bytes))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        hex::decode(&s).map_err(serde::de::Error::custom)
    }
}
