// Execute handler — executes a fully-approved proposal
//
// Expected accounts:
// - accounts[0]: multisig_state (PDA) — stores proposals and state
// - accounts[1]: executor account (must be authorized = is a signer, must be member)
//
// For Transfer actions, the vault balance is deducted from the multisig state account.
// (In a full implementation, a chained call to the token program would handle the transfer.)

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};
use multisig_core::{MultisigState, ProposalAction, ProposalStatus};

pub fn handle(
    accounts: &[AccountWithMetadata],
    proposal_index: u64,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 2, "Execute requires multisig_state + executor accounts");

    let multisig_account = &accounts[0];
    let executor_account = &accounts[1];

    assert!(executor_account.is_authorized, "Executor must sign the transaction");

    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let mut state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");

    let executor_id = *executor_account.account_id.value();
    assert!(state.is_member(&executor_id), "Executor is not a multisig member");

    // Find proposal and verify it's ready
    let threshold = state.threshold;
    let proposal = state.get_proposal_mut(proposal_index)
        .expect("Proposal not found");

    assert_eq!(proposal.status, ProposalStatus::Active, "Proposal is not active");
    assert!(
        proposal.has_threshold(threshold),
        "Proposal does not have enough approvals: need {}, have {}",
        threshold,
        proposal.approved.len()
    );

    // Mark as executed
    proposal.status = ProposalStatus::Executed;
    let action = proposal.action.clone();

    // Execute the action
    let mut multisig_post = multisig_account.account.clone();

    match &action {
        ProposalAction::Transfer { recipient: _, amount } => {
            // Deduct from vault (multisig state account balance for now)
            assert!(
                multisig_post.balance >= *amount,
                "Insufficient vault balance: have {}, need {}",
                multisig_post.balance,
                amount
            );
            multisig_post.balance -= amount;
            // TODO: chained call to transfer to recipient
        }

        ProposalAction::AddMember { new_member } => {
            assert!(!state.is_member(new_member), "Already a member");
            assert!(state.members.len() < 10, "Maximum 10 members");
            state.members.push(*new_member);
            state.member_count = state.members.len() as u8;
        }

        ProposalAction::RemoveMember { member_to_remove } => {
            assert!(state.is_member(member_to_remove), "Not a member");
            state.members.retain(|m| m != member_to_remove);
            state.member_count = state.members.len() as u8;
            assert!(
                state.threshold as usize <= state.members.len(),
                "Cannot remove member: would make threshold unreachable"
            );
        }

        ProposalAction::ChangeThreshold { new_threshold } => {
            assert!(*new_threshold >= 1, "Threshold must be at least 1");
            assert!(
                (*new_threshold as usize) <= state.members.len(),
                "Threshold cannot exceed member count"
            );
            state.threshold = *new_threshold;
        }
    }

    // Remove all proposals after execution
    state.clear_all_proposals();

    // Serialize updated state
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_post.data = state_bytes.try_into().unwrap();

    // Must return post states for ALL input accounts
    let executor_post = executor_account.account.clone();

    (vec![AccountPostState::new(multisig_post), AccountPostState::new(executor_post)], vec![])
}

#[cfg(test)]
mod tests {
    use super::*;
    use nssa_core::account::{Account, AccountId};
    use multisig_core::ProposalAction;

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

    fn make_approved_transfer_state(threshold: u8, members: Vec<[u8; 32]>, approvers: &[[u8; 32]], amount: u128) -> Vec<u8> {
        let mut state = MultisigState::new([0u8; 32], threshold, members);
        state.create_proposal(
            ProposalAction::Transfer {
                recipient: AccountId::new([99u8; 32]),
                amount,
            },
            approvers[0],
        );
        // Additional approvals beyond the proposer
        for approver in &approvers[1..] {
            let proposal = state.get_proposal_mut(1).unwrap();
            proposal.approve(*approver);
        }
        borsh::to_vec(&state).unwrap()
    }

    #[test]
    fn test_execute_transfer() {
        let members = vec![[1u8; 32], [2u8; 32]];
        let state_data = make_approved_transfer_state(2, members, &[[1u8; 32], [2u8; 32]], 100);

        let accounts = vec![
            make_account(&[10u8; 32], 1000, state_data, false),
            make_account(&[1u8; 32], 0, vec![], true),
        ];

        let (post_states, _) = handle(&accounts, 1);

        let post = &post_states[0].account();
        assert_eq!(post.balance, 900); // 1000 - 100
        let state: MultisigState = borsh::from_slice(&Vec::from(post.data.clone())).unwrap();
        // Executed proposals get cleaned up
        assert_eq!(state.proposals.len(), 0);
    }

    #[test]
    fn test_execute_add_member() {
        let members = vec![[1u8; 32], [2u8; 32]];
        let mut state = MultisigState::new([0u8; 32], 2, members);
        state.create_proposal(
            ProposalAction::AddMember { new_member: [3u8; 32] },
            [1u8; 32],
        );
        state.get_proposal_mut(1).unwrap().approve([2u8; 32]);
        let state_data = borsh::to_vec(&state).unwrap();

        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data, false),
            make_account(&[1u8; 32], 0, vec![], true),
        ];

        let (post_states, _) = handle(&accounts, 1);

        let state: MultisigState = borsh::from_slice(&Vec::from(post_states[0].account().data.clone())).unwrap();
        assert_eq!(state.members.len(), 3);
        assert!(state.is_member(&[3u8; 32]));
    }

    #[test]
    fn test_execute_change_threshold() {
        let members = vec![[1u8; 32], [2u8; 32], [3u8; 32]];
        let mut state = MultisigState::new([0u8; 32], 2, members);
        state.create_proposal(
            ProposalAction::ChangeThreshold { new_threshold: 3 },
            [1u8; 32],
        );
        state.get_proposal_mut(1).unwrap().approve([2u8; 32]);
        let state_data = borsh::to_vec(&state).unwrap();

        let accounts = vec![
            make_account(&[10u8; 32], 0, state_data, false),
            make_account(&[1u8; 32], 0, vec![], true),
        ];

        let (post_states, _) = handle(&accounts, 1);

        let state: MultisigState = borsh::from_slice(&Vec::from(post_states[0].account().data.clone())).unwrap();
        assert_eq!(state.threshold, 3);
    }

    #[test]
    #[should_panic(expected = "does not have enough approvals")]
    fn test_execute_insufficient_approvals() {
        let members = vec![[1u8; 32], [2u8; 32], [3u8; 32]];
        let mut state = MultisigState::new([0u8; 32], 2, members);
        state.create_proposal(
            ProposalAction::Transfer {
                recipient: AccountId::new([99u8; 32]),
                amount: 100,
            },
            [1u8; 32],
        );
        // Only 1 approval (proposer), need 2
        let state_data = borsh::to_vec(&state).unwrap();

        let accounts = vec![
            make_account(&[10u8; 32], 1000, state_data, false),
            make_account(&[1u8; 32], 0, vec![], true),
        ];

        handle(&accounts, 1);
    }

    #[test]
    #[should_panic(expected = "Insufficient vault balance")]
    fn test_execute_insufficient_balance() {
        let members = vec![[1u8; 32], [2u8; 32]];
        let state_data = make_approved_transfer_state(2, members, &[[1u8; 32], [2u8; 32]], 1000);

        let accounts = vec![
            make_account(&[10u8; 32], 100, state_data, false), // only 100 balance
            make_account(&[1u8; 32], 0, vec![], true),
        ];

        handle(&accounts, 1);
    }

    #[test]
    fn test_execute_1_of_1() {
        let members = vec![[1u8; 32]];
        let state_data = make_approved_transfer_state(1, members, &[[1u8; 32]], 50);

        let accounts = vec![
            make_account(&[10u8; 32], 500, state_data, false),
            make_account(&[1u8; 32], 0, vec![], true),
        ];

        let (post_states, _) = handle(&accounts, 1);
        assert_eq!(post_states[0].account().balance, 450);
    }
}
