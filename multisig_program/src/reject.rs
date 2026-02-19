// Reject handler — any member rejects an existing proposal
//
// Expected accounts:
// - accounts[0]: multisig_state (PDA)
// - accounts[1]: rejector account (must be authorized = is a signer)

use nssa_core::account::AccountWithMetadata;
use nssa_core::program::{AccountPostState, ChainedCall};
use multisig_core::{MultisigState, ProposalStatus};

pub fn handle(
    accounts: &[AccountWithMetadata],
    proposal_index: u64,
) -> (Vec<AccountPostState>, Vec<ChainedCall>) {
    assert!(accounts.len() >= 2, "Reject requires multisig_state + rejector accounts");

    let multisig_account = &accounts[0];
    let rejector_account = &accounts[1];

    assert!(rejector_account.is_authorized, "Rejector must sign the transaction");

    let state_data: Vec<u8> = multisig_account.account.data.clone().into();
    let mut state: MultisigState = borsh::from_slice(&state_data)
        .expect("Failed to deserialize multisig state");

    let rejector_id = *rejector_account.account_id.value();
    assert!(state.is_member(&rejector_id), "Rejector is not a multisig member");

    let threshold = state.threshold;
    let member_count = state.member_count;

    let proposal = state.get_proposal_mut(proposal_index)
        .expect("Proposal not found");

    assert_eq!(proposal.status, ProposalStatus::Active, "Proposal is not active");

    let is_new = proposal.reject(rejector_id);
    assert!(is_new, "Member has already rejected this proposal");

    if proposal.is_dead(threshold, member_count) {
        proposal.status = ProposalStatus::Rejected;
    }

    let mut multisig_post = multisig_account.account.clone();
    let state_bytes = borsh::to_vec(&state).unwrap();
    multisig_post.data = state_bytes.try_into().unwrap();

    let rejector_post = rejector_account.account.clone();

    (vec![AccountPostState::new(multisig_post), AccountPostState::new(rejector_post)], vec![])
}

#[cfg(test)]
mod tests {
    use super::*;
    use nssa_core::account::{Account, AccountId};
    use nssa_core::program::ProgramId;

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
        let fake_program_id: ProgramId = bytemuck::cast([42u8; 32]);
        state.create_proposal(
            proposer,
            fake_program_id,
            vec![0u32],
            1,
            vec![],
        );
        borsh::to_vec(&state).unwrap()
    }

    #[test]
    fn test_reject_adds_rejection() {
        let members = vec![[1u8; 32], [2u8; 32], [3u8; 32]];
        let state_data = make_state_with_proposal(2, members, [1u8; 32]);

        let accounts = vec![
            make_account(&[10u8; 32], state_data, false),
            make_account(&[2u8; 32], vec![], true),
        ];

        let (post_states, _) = handle(&accounts, 1);

        let state: MultisigState = borsh::from_slice(&Vec::from(post_states[0].account().data.clone())).unwrap();
        let proposal = state.get_proposal(1).unwrap();
        assert_eq!(proposal.rejected.len(), 1);
        assert_eq!(proposal.approved.len(), 1);
    }

    #[test]
    fn test_reject_auto_marks_dead_proposal() {
        let members = vec![[1u8; 32], [2u8; 32]];
        let state_data = make_state_with_proposal(2, members, [1u8; 32]);

        let accounts = vec![
            make_account(&[10u8; 32], state_data, false),
            make_account(&[2u8; 32], vec![], true),
        ];

        let (post_states, _) = handle(&accounts, 1);

        let state: MultisigState = borsh::from_slice(&Vec::from(post_states[0].account().data.clone())).unwrap();
        let proposal = state.get_proposal(1).unwrap();
        assert_eq!(proposal.status, ProposalStatus::Rejected);
    }
}
