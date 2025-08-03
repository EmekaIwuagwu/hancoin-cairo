// Escrow Contract Tests
use starknet::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};
use super::super::contracts::escrow::{EscrowContract, IEscrowContractDispatcher, IEscrowContractDispatcherTrait, EscrowOrder, EscrowStatus};

fn setup() -> (ContractAddress, ContractAddress, ContractAddress, IEscrowContractDispatcher) {
    let owner = starknet::contract_address_const::<1>();
    let hancoin_token = starknet::contract_address_const::<2>();
    let admin_wallet = starknet::contract_address_const::<3>();
    let contract_address = starknet::contract_address_const::<4>();
    
    set_contract_address(contract_address);
    set_caller_address(owner);
    set_block_timestamp(1000000);
    
    let escrow_dispatcher = IEscrowContractDispatcher { contract_address };
    
    (owner, hancoin_token, admin_wallet, escrow_dispatcher)
}

#[test]
fn test_create_escrow() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    set_caller_address(buyer);
    
    let amount = 50000 * 1000000000000000000; // 50k HNXZ
    let property_id = 'PROP001';
    let timeout_duration = 86400 * 30; // 30 days
    
    // Create escrow
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    
    // Verify escrow was created
    assert(order_id == 1, 'Wrong order ID');
    
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.buyer == buyer, 'Wrong buyer');
    assert(order.seller == seller, 'Wrong seller');
    assert(order.amount == amount, 'Wrong amount');
    assert(order.property_id == property_id, 'Wrong property ID');
    assert(order.status == EscrowStatus::Created, 'Wrong status');
}

#[test]
fn test_fund_escrow() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create escrow
    set_caller_address(buyer);
    let amount = 25000 * 1000000000000000000; // 25k HNXZ
    let property_id = 'PROP002';
    let timeout_duration = 86400 * 15; // 15 days
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    
    // Fund escrow
    escrow_contract.fund_escrow(order_id);
    
    // Verify escrow is funded
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.status == EscrowStatus::Funded, 'Should be funded');
    
    // Check total escrowed
    assert(escrow_contract.get_total_escrowed() == amount, 'Wrong total escrowed');
}

#[test]
fn test_confirm_transaction() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create and fund escrow
    set_caller_address(buyer);
    let amount = 10000 * 1000000000000000000; // 10k HNXZ
    let property_id = 'PROP003';
    let timeout_duration = 86400 * 20;
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    escrow_contract.fund_escrow(order_id);
    
    // Buyer confirms
    escrow_contract.confirm_transaction(order_id);
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.buyer_confirmed == true, 'Buyer should have confirmed');
    assert(order.status == EscrowStatus::Funded, 'Status should still be funded');
    
    // Seller confirms
    set_caller_address(seller);
    escrow_contract.confirm_transaction(order_id);
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.seller_confirmed == true, 'Seller should have confirmed');
    assert(order.status == EscrowStatus::InProgress, 'Status should be in progress');
}

#[test]
fn test_release_escrow() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create, fund, and confirm escrow
    set_caller_address(buyer);
    let amount = 15000 * 1000000000000000000; // 15k HNXZ
    let property_id = 'PROP004';
    let timeout_duration = 86400 * 25;
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    escrow_contract.fund_escrow(order_id);
    escrow_contract.confirm_transaction(order_id);
    
    set_caller_address(seller);
    escrow_contract.confirm_transaction(order_id);
    
    // Release escrow (automatic after both confirmations)
    escrow_contract.release_escrow(order_id);
    
    // Verify escrow is completed
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.status == EscrowStatus::Completed, 'Should be completed');
    
    // Check statistics
    assert(escrow_contract.get_total_escrowed() == 0, 'Should have no escrowed funds');
    let expected_fee = (amount * 250) / 10000; // 2.5% fee
    assert(escrow_contract.get_total_fees_collected() == expected_fee, 'Wrong fees collected');
}

#[test]
fn test_raise_dispute() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create and fund escrow
    set_caller_address(buyer);
    let amount = 8000 * 1000000000000000000; // 8k HNXZ
    let property_id = 'PROP005';
    let timeout_duration = 86400 * 30;
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    escrow_contract.fund_escrow(order_id);
    
    // Raise dispute
    escrow_contract.raise_dispute(order_id);
    
    // Verify dispute is raised
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.dispute_raised == true, 'Dispute should be raised');
    assert(order.dispute_by == buyer, 'Wrong dispute raiser');
    assert(order.status == EscrowStatus::Disputed, 'Should be disputed');
}

#[test]
fn test_resolve_dispute() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create, fund escrow and raise dispute
    set_caller_address(buyer);
    let amount = 12000 * 1000000000000000000; // 12k HNXZ
    let property_id = 'PROP006';
    let timeout_duration = 86400 * 30;
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    escrow_contract.fund_escrow(order_id);
    escrow_contract.raise_dispute(order_id);
    
    // Resolve dispute (as owner) - 60% to buyer, 40% to seller
    set_caller_address(owner);
    let buyer_percentage = 6000_u256; // 60%
    escrow_contract.resolve_dispute(order_id, buyer_percentage);
    
    // Verify dispute is resolved
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.status == EscrowStatus::Resolved, 'Should be resolved');
    
    // Check statistics updated
    assert(escrow_contract.get_total_escrowed() == 0, 'Should have no escrowed funds');
}

#[test]
fn test_cancel_escrow() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create escrow (not funded)
    set_caller_address(buyer);
    let amount = 5000 * 1000000000000000000; // 5k HNXZ
    let property_id = 'PROP007';
    let timeout_duration = 86400 * 20;
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    
    // Cancel escrow (as buyer before funding)
    escrow_contract.cancel_escrow(order_id);
    
    // Verify escrow is cancelled
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.status == EscrowStatus::Cancelled, 'Should be cancelled');
}

#[test]
fn test_handle_expired_escrow() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create and fund escrow with short timeout
    set_caller_address(buyer);
    let amount = 3000 * 1000000000000000000; // 3k HNXZ
    let property_id = 'PROP008';
    let timeout_duration = 3600; // 1 hour
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    escrow_contract.fund_escrow(order_id);
    
    // Fast forward time past timeout
    set_block_timestamp(1000000 + timeout_duration + 1);
    
    // Handle expired escrow
    escrow_contract.handle_expired_escrow(order_id);
    
    // Verify escrow is expired
    let order = escrow_contract.get_escrow_order(order_id);
    assert(order.status == EscrowStatus::Expired, 'Should be expired');
    
    // Check funds returned
    assert(escrow_contract.get_total_escrowed() == 0, 'Should have no escrowed funds');
}

#[test]
#[should_panic(expected: ('Buyer cannot be seller',))]
fn test_buyer_cannot_be_seller() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let user = starknet::contract_address_const::<5>();
    
    set_caller_address(user);
    
    let amount = 1000 * 1000000000000000000;
    let property_id = 'PROP009';
    let timeout_duration = 86400 * 30;
    
    // Try to create escrow where buyer and seller are the same
    escrow_contract.create_escrow(user, amount, property_id, timeout_duration);
}

#[test]
#[should_panic(expected: ('Amount below minimum',))]
fn test_amount_below_minimum() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    set_caller_address(buyer);
    
    let amount = 500 * 1000000000000000000; // 500 HNXZ (below 1000 minimum)
    let property_id = 'PROP010';
    let timeout_duration = 86400 * 30;
    
    escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
}

#[test]
#[should_panic(expected: ('Only buyer can fund',))]
fn test_only_buyer_can_fund() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create escrow
    set_caller_address(buyer);
    let amount = 2000 * 1000000000000000000;
    let property_id = 'PROP011';
    let timeout_duration = 86400 * 30;
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    
    // Try to fund as seller
    set_caller_address(seller);
    escrow_contract.fund_escrow(order_id);
}

#[test]
fn test_admin_functions() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    
    // Test setting escrow fee rate
    let new_fee_rate = 500_u256; // 5%
    escrow_contract.set_escrow_fee_rate(new_fee_rate);
    assert(escrow_contract.get_escrow_fee_rate() == new_fee_rate, 'Fee rate not updated');
    
    // Test setting admin wallet
    let new_admin = starknet::contract_address_const::<7>();
    escrow_contract.set_admin_wallet(new_admin);
    
    // Test setting minimum escrow amount
    let new_min = 2000 * 1000000000000000000; // 2k HNXZ
    escrow_contract.set_min_escrow_amount(new_min);
    
    // Test setting maximum escrow amount
    let new_max = 20000000 * 1000000000000000000; // 20M HNXZ
    escrow_contract.set_max_escrow_amount(new_max);
}

#[test]
fn test_get_escrow_status() {
    let (owner, hancoin_token, admin_wallet, escrow_contract) = setup();
    let buyer = starknet::contract_address_const::<5>();
    let seller = starknet::contract_address_const::<6>();
    
    // Create escrow
    set_caller_address(buyer);
    let amount = 1500 * 1000000000000000000;
    let property_id = 'PROP012';
    let timeout_duration = 86400 * 30;
    
    let order_id = escrow_contract.create_escrow(seller, amount, property_id, timeout_duration);
    
    // Check initial status
    assert(escrow_contract.get_escrow_status(order_id) == EscrowStatus::Created, 'Should be created');
    
    // Fund and check status
    escrow_contract.fund_escrow(order_id);
    assert(escrow_contract.get_escrow_status(order_id) == EscrowStatus::Funded, 'Should be funded');
}