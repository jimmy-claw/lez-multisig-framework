// Propose handler — any member creates a new proposal (auto-approves)
//
// Expected accounts:
// - accounts[0]: multisig_state (PDA) — stores proposals
// - accounts[1]: proposer account (must be authorized = is a signer)
//
// The proposer must be a member and must have is_authorized = true.

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};
use multisig_core::{MultisigState, ProposalAction};

pub fn handle(
    accounts: &[AccountWithMetadata],
    action: &ProposalAction,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 2, "Propose requires multisig_state + proposer accounts");

    let multisig_account = &accounts[0];
    let proposer_account = &accounts[1];

    // Proposer must be authorized (i.e., signed the transaction)
    assert!(proposer_account.is_authorized, "Proposer must sign the transaction");

    // Deserialize state
    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let mut state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");

    // Proposer must be a member
    let proposer_id = *proposer_account.account_id.value();
    assert!(state.is_member(&proposer_id), "Proposer is not a multisig member");

    // Create proposal (proposer auto-approves)
    let index = state.create_proposal(action.clone(), proposer_id);

    // Check if already at threshold (1-of-N case)
    if let Some(proposal) = state.get_proposal(index) {
        if proposal.has_threshold(state.threshold) {
            // Mark as approved but don't auto-execute — explicit Execute required
        }
    }

    // Serialize updated state
    let mut multisig_post = multisig_account.account.clone();
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_post.data = state_bytes.try_into().unwrap();

    // Must return post states for ALL input accounts (sequencer validates length match)
    let proposer_post = proposer_account.account.clone();

    (vec![AccountPostState::new(multisig_post), AccountPostState::new(proposer_post)], vec![])
}

#[cfg(test)]
mod tests {
    use super::*;
    use nssa_core::account::{Account, AccountId};

    fn make_account(id: &[u8; 32], balance: u128, data: Vec<u8>, authorized: bool) -> AccountWithMetadata {
        let mut account = Account::default();
        account.balance = balance;
        account.data = data.try_into().unwrap();
        AccountWithMetadata {
            account_id: AccountId::new(*id),
            account,
            is_authorized: authorized,
        }
    }

    fn make_multisig_state(threshold: u8, members: Vec<[u8; 32]>) -> Vec<u8> {
        let state = MultisigState::new([0u8; 32], threshold, members);
        borsh::to_vec(&state).unwrap()
    }

    #[test]
    fn test_propose_creates_proposal() {
        let member = [1u8; 32];
        let state_data = make_multisig_state(2, vec![member, [2u8; 32], [3u8; 32]]);

        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data, false),
            make_account(&member, 0, vec![], true),
        ];

        let action = ProposalAction::Transfer {
            recipient: AccountId::new([99u8; 32]),
            amount: 100,
        };

        let (post_states, _) = handle(&accounts, &action);

        let state: MultisigState = borsh::from_slice(&Vec::from(post_states[0].account().data.clone())).unwrap();
        assert_eq!(state.transaction_index, 1);
        assert_eq!(state.proposals.len(), 1);
        assert_eq!(state.proposals[0].index, 1);
        assert_eq!(state.proposals[0].approved.len(), 1); // auto-approved by proposer
        assert_eq!(state.proposals[0].approved[0], member);
    }

    #[test]
    #[should_panic(expected = "Proposer must sign")]
    fn test_propose_unauthorized_fails() {
        let member = [1u8; 32];
        let state_data = make_multisig_state(2, vec![member]);

        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data, false),
            make_account(&member, 0, vec![], false), // not authorized
        ];

        let action = ProposalAction::Transfer {
            recipient: AccountId::new([99u8; 32]),
            amount: 100,
        };

        handle(&accounts, &action);
    }

    #[test]
    #[should_panic(expected = "not a multisig member")]
    fn test_propose_non_member_fails() {
        let state_data = make_multisig_state(1, vec![[1u8; 32]]);

        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data, false),
            make_account(&[99u8; 32], 0, vec![], true), // authorized but not a member
        ];

        let action = ProposalAction::Transfer {
            recipient: AccountId::new([99u8; 32]),
            amount: 100,
        };

        handle(&accounts, &action);
    }
}
