// SPDX-License-Identifier: MIT
// Hancoin (HNXZ) Token Contract - ERC20 Implementation for Homebase Real Estate Platform

#[starknet::contract]
mod HancoinToken {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // Ownable Mixin
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        // Additional storage for Homebase features
        paymaster_enabled: bool,
        authorized_paymasters: LegacyMap::<ContractAddress, bool>,
        gas_fee_rate: u256, // Rate for gas fee calculation in HNXZ
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        PaymasterSet: PaymasterSet,
        GasFeeCharged: GasFeeCharged,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymasterSet {
        paymaster: ContractAddress,
        enabled: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct GasFeeCharged {
        user: ContractAddress,
        amount: u256,
    }

    // Constructor - Deploy with initial supply
    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        let name = "Hancoin";
        let symbol = "HNXZ";
        let initial_supply: u256 = 1_000_000_000 * 1000000000000000000; // 1B tokens with 18 decimals
        
        self.erc20.initializer(name, symbol);
        self.ownable.initializer(owner);
        self.erc20._mint(owner, initial_supply);
        
        // Initialize paymaster settings
        self.paymaster_enabled.write(true);
        self.gas_fee_rate.write(1000000000000000); // 0.001 HNXZ per gas unit
    }

    #[abi(embed_v0)]
    impl HancoinTokenImpl of super::IHancoinToken<ContractState> {
        // Paymaster functionality - charge gas fees in HNXZ
        fn pay_gas_fee(ref self: ContractState, user: ContractAddress, gas_amount: u256) -> bool {
            assert(self.paymaster_enabled.read(), 'Paymaster not enabled');
            assert(self.authorized_paymasters.read(get_caller_address()), 'Unauthorized paymaster');
            
            let fee_amount = gas_amount * self.gas_fee_rate.read();
            let user_balance = self.erc20.balance_of(user);
            
            if user_balance >= fee_amount {
                self.erc20._transfer(user, get_contract_address(), fee_amount);
                self.emit(GasFeeCharged { user, amount: fee_amount });
                true
            } else {
                false
            }
        }

        fn set_paymaster(ref self: ContractState, paymaster: ContractAddress, enabled: bool) {
            self.ownable.assert_only_owner();
            self.authorized_paymasters.write(paymaster, enabled);
            self.emit(PaymasterSet { paymaster, enabled });
        }

        fn set_gas_fee_rate(ref self: ContractState, new_rate: u256) {
            self.ownable.assert_only_owner();
            self.gas_fee_rate.write(new_rate);
        }

        fn get_gas_fee_rate(self: @ContractState) -> u256 {
            self.gas_fee_rate.read()
        }

        fn is_paymaster_enabled(self: @ContractState) -> bool {
            self.paymaster_enabled.read()
        }

        // Mint additional tokens (only owner)
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            self.erc20._mint(to, amount);
        }

        // Burn tokens
        fn burn(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            self.erc20._burn(caller, amount);
        }

        // Get total supply with proper decimals display
        fn total_supply_formatted(self: @ContractState) -> u256 {
            self.erc20.total_supply() / 1000000000000000000 // Return in whole tokens
        }
    }

    #[starknet::interface]
    trait IHancoinToken<TContractState> {
        fn pay_gas_fee(ref self: TContractState, user: ContractAddress, gas_amount: u256) -> bool;
        fn set_paymaster(ref self: TContractState, paymaster: ContractAddress, enabled: bool);
        fn set_gas_fee_rate(ref self: TContractState, new_rate: u256);
        fn get_gas_fee_rate(self: @TContractState) -> u256;
        fn is_paymaster_enabled(self: @TContractState) -> bool;
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn burn(ref self: TContractState, amount: u256);
        fn total_supply_formatted(self: @TContractState) -> u256;
    }
}