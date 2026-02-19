// Approve handler — any member approves an existing proposal
//
// Expected accounts:
// - accounts[0]: multisig_state (PDA)
// - accounts[1]: approver account (must be authorized = is a signer)

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};
use multisig_core::{MultisigState, ProposalStatus};

pub fn handle(
    accounts: &[AccountWithMetadata],
    proposal_index: u64,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 2, "Approve requires multisig_state + approver accounts");

    let multisig_account = &accounts[0];
    let approver_account = &accounts[1];

    assert!(approver_account.is_authorized, "Approver must sign the transaction");

    // Deserialize state
    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let mut state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");

    let approver_id = *approver_account.account_id.value();
    assert!(state.is_member(&approver_id), "Approver is not a multisig member");

    // Find and approve the proposal
    let proposal = state.get_proposal_mut(proposal_index)
        .expect("Proposal not found");

    assert_eq!(proposal.status, ProposalStatus::Active, "Proposal is not active");

    let is_new = proposal.approve(approver_id);
    assert!(is_new, "Member has already approved this proposal");

    // Serialize updated state
    let mut multisig_post = multisig_account.account.clone();
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_post.data = state_bytes.try_into().unwrap();

    // Must return post states for ALL input accounts
    let approver_post = approver_account.account.clone();

    (vec![AccountPostState::new(multisig_post), AccountPostState::new(approver_post)], vec![])
}

#[cfg(test)]
mod tests {
    use super::*;
    use nssa_core::account::{Account, AccountId};
    use multisig_core::ProposalAction;

    fn make_account(id: &[u8; 32], data: Vec<u8>, authorized: bool) -> AccountWithMetadata {
        let mut account = Account::default();
        account.data = data.try_into().unwrap();
        AccountWithMetadata {
            account_id: AccountId::new(*id),
            account,
            is_authorized: authorized,
        }
    }

    fn make_state_with_proposal(threshold: u8, members: Vec<[u8; 32]>, proposer: [u8; 32]) -> Vec<u8> {
        let mut state = MultisigState::new([0u8; 32], threshold, members);
        state.create_proposal(
            ProposalAction::Transfer {
                recipient: AccountId::new([99u8; 32]),
                amount: 100,
            },
            proposer,
        );
        borsh::to_vec(&state).unwrap()
    }

    #[test]
    fn test_approve_adds_approval() {
        let members = vec![[1u8; 32], [2u8; 32], [3u8; 32]];
        let state_data = make_state_with_proposal(2, members, [1u8; 32]);

        let accounts = vec![
            make_account(&[10u8; 32], state_data, false),
            make_account(&[2u8; 32], vec![], true),
        ];

        let (post_states, _) = handle(&accounts, 1);

        let state: MultisigState = borsh::from_slice(&Vec::from(post_states[0].account().data.clone())).unwrap();
        let proposal = state.get_proposal(1).unwrap();
        assert_eq!(proposal.approved.len(), 2); // proposer + approver
        assert!(proposal.approved.contains(&[1u8; 32]));
        assert!(proposal.approved.contains(&[2u8; 32]));
    }

    #[test]
    #[should_panic(expected = "already approved")]
    fn test_approve_duplicate_fails() {
        let members = vec![[1u8; 32], [2u8; 32]];
        let state_data = make_state_with_proposal(2, members, [1u8; 32]);

        let accounts = vec![
            make_account(&[10u8; 32], state_data, false),
            make_account(&[1u8; 32], vec![], true), // proposer already approved
        ];

        handle(&accounts, 1);
    }

    #[test]
    #[should_panic(expected = "Proposal not found")]
    fn test_approve_nonexistent_proposal() {
        let members = vec![[1u8; 32], [2u8; 32]];
        let state_data = make_state_with_proposal(2, members, [1u8; 32]);

        let accounts = vec![
            make_account(&[10u8; 32], state_data, false),
            make_account(&[2u8; 32], vec![], true),
        ];

        handle(&accounts, 99); // wrong index
    }
}
