// Token Contract Tests
use starknet::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address};
use super::super::contracts::token::{HancoinToken, IHancoinTokenDispatcher, IHancoinTokenDispatcherTrait};
use openzeppelin::token::erc20::{ERC20Component, IERC20Dispatcher, IERC20DispatcherTrait};

fn setup() -> (ContractAddress, IHancoinTokenDispatcher, IERC20Dispatcher) {
    let owner = starknet::contract_address_const::<1>();
    let contract_address = starknet::contract_address_const::<2>();
    
    set_contract_address(contract_address);
    set_caller_address(owner);
    
    let hancoin_dispatcher = IHancoinTokenDispatcher { contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address };
    
    (owner, hancoin_dispatcher, erc20_dispatcher)
}

#[test]
fn test_token_deployment() {
    let (owner, hancoin, erc20) = setup();
    
    // Test initial values
    assert(erc20.name() == "Hancoin", 'Wrong token name');
    assert(erc20.symbol() == "HNXZ", 'Wrong token symbol');
    assert(erc20.decimals() == 18, 'Wrong decimals');
    
    // Test initial supply
    let expected_supply = 1000000000 * 1000000000000000000; // 1B tokens
    assert(erc20.total_supply() == expected_supply, 'Wrong initial supply');
    assert(erc20.balance_of(owner) == expected_supply, 'Wrong owner balance');
}

#[test]
fn test_token_transfer() {
    let (owner, hancoin, erc20) = setup();
    let recipient = starknet::contract_address_const::<3>();
    let amount = 1000 * 1000000000000000000; // 1000 tokens
    
    // Transfer tokens
    erc20.transfer(recipient, amount);
    
    // Check balances
    let expected_owner_balance = (1000000000 * 1000000000000000000) - amount;
    assert(erc20.balance_of(owner) == expected_owner_balance, 'Wrong owner balance after transfer');
    assert(erc20.balance_of(recipient) == amount, 'Wrong recipient balance');
}

#[test]
fn test_paymaster_functionality() {
    let (owner, hancoin, erc20) = setup();
    let paymaster = starknet::contract_address_const::<4>();
    let user = starknet::contract_address_const::<5>();
    let gas_amount = 100000_u256;
    
    // Set paymaster
    hancoin.set_paymaster(paymaster, true);
    
    // Transfer some tokens to user
    let user_balance = 10000 * 1000000000000000000; // 10k tokens
    erc20.transfer(user, user_balance);
    
    // Test gas fee payment (as paymaster)
    set_caller_address(paymaster);
    let success = hancoin.pay_gas_fee(user, gas_amount);
    assert(success, 'Gas fee payment failed');
}

#[test]
fn test_mint_and_burn() {
    let (owner, hancoin, erc20) = setup();
    let recipient = starknet::contract_address_const::<6>();
    let mint_amount = 1000 * 1000000000000000000; // 1000 tokens
    
    // Test minting (as owner)
    let initial_supply = erc20.total_supply();
    hancoin.mint(recipient, mint_amount);
    
    assert(erc20.total_supply() == initial_supply + mint_amount, 'Wrong supply after mint');
    assert(erc20.balance_of(recipient) == mint_amount, 'Wrong recipient balance after mint');
    
    // Test burning (as recipient)
    set_caller_address(recipient);
    let burn_amount = 500 * 1000000000000000000; // 500 tokens
    hancoin.burn(burn_amount);
    
    assert(erc20.balance_of(recipient) == mint_amount - burn_amount, 'Wrong balance after burn');
}

#[test]
fn test_gas_fee_rate() {
    let (owner, hancoin, erc20) = setup();
    
    // Test default gas fee rate
    let default_rate = hancoin.get_gas_fee_rate();
    assert(default_rate == 1000000000000000, 'Wrong default gas fee rate');
    
    // Test setting new rate
    let new_rate = 2000000000000000_u256;
    hancoin.set_gas_fee_rate(new_rate);
    assert(hancoin.get_gas_fee_rate() == new_rate, 'Gas fee rate not updated');
}

#[test]
fn test_paymaster_enabled() {
    let (owner, hancoin, erc20) = setup();
    
    // Test paymaster is enabled by default
    assert(hancoin.is_paymaster_enabled(), 'Paymaster should be enabled');
}

#[test]
#[should_panic(expected: ('Unauthorized paymaster',))]
fn test_unauthorized_paymaster() {
    let (owner, hancoin, erc20) = setup();
    let unauthorized = starknet::contract_address_const::<7>();
    let user = starknet::contract_address_const::<8>();
    
    // Try to pay gas fee as unauthorized paymaster
    set_caller_address(unauthorized);
    hancoin.pay_gas_fee(user, 1000);
}

#[test]
fn test_formatted_supply() {
    let (owner, hancoin, erc20) = setup();
    
    // Test formatted supply (should return in whole tokens)
    let formatted_supply = hancoin.total_supply_formatted();
    assert(formatted_supply == 1000000000, 'Wrong formatted supply');
}