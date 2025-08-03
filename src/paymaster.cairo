// SPDX-License-Identifier: MIT
// Paymaster Contract - Handles gas fee payments in HNXZ tokens

#[starknet::contract]
mod Paymaster {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_tx_info};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        hancoin_token: ContractAddress,
        gas_price_oracle: ContractAddress,
        base_gas_fee: u256, // Base fee in HNXZ per gas unit
        fee_multiplier: u256, // Multiplier for dynamic pricing (basis points)
        collected_fees: u256, // Total fees collected
        user_gas_allowances: LegacyMap::<ContractAddress, u256>, // Pre-approved gas allowances
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        GasFeePaid: GasFeePaid,
        GasAllowanceSet: GasAllowanceSet,
        FeesWithdrawn: FeesWithdrawn,
    }

    #[derive(Drop, starknet::Event)]
    struct GasFeePaid {
        user: ContractAddress,
        gas_used: u256,
        fee_amount: u256,
        transaction_hash: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct GasAllowanceSet {
        user: ContractAddress,
        allowance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct FeesWithdrawn {
        to: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        hancoin_token: ContractAddress,
        base_gas_fee: u256
    ) {
        self.ownable.initializer(owner);
        self.hancoin_token.write(hancoin_token);
        self.base_gas_fee.write(base_gas_fee);
        self.fee_multiplier.write(10000); // 100% (no markup initially)
        self.collected_fees.write(0);
    }

    #[abi(embed_v0)]
    impl PaymasterImpl of super::IPaymaster<ContractState> {
        // Pre-approve gas allowance for a user
        fn set_gas_allowance(ref self: ContractState, user: ContractAddress, allowance: u256) {
            self.ownable.assert_only_owner();
            self.user_gas_allowances.write(user, allowance);
            self.emit(GasAllowanceSet { user, allowance });
        }

        // Calculate gas fee in HNXZ tokens
        fn calculate_gas_fee(self: @ContractState, gas_used: u256) -> u256 {
            let base_fee = self.base_gas_fee.read();
            let multiplier = self.fee_multiplier.read();
            (gas_used * base_fee * multiplier) / 10000
        }

        // Pay gas fee in HNXZ (called by transaction executor)
        fn pay_gas_fee(ref self: ContractState, user: ContractAddress, gas_used: u256) -> bool {
            let fee_amount = self.calculate_gas_fee(gas_used);
            let hancoin_token = self.hancoin_token.read();
            
            // Check if user has sufficient allowance
            let current_allowance = self.user_gas_allowances.read(user);
            if current_allowance < fee_amount {
                return false;
            }

            // Attempt to transfer HNXZ from user to paymaster contract
            let transfer_result = self._transfer_from_user(user, fee_amount, hancoin_token);
            
            if transfer_result {
                // Deduct from allowance
                self.user_gas_allowances.write(user, current_allowance - fee_amount);
                
                // Update collected fees
                let current_fees = self.collected_fees.read();
                self.collected_fees.write(current_fees + fee_amount);
                
                // Emit event
                let tx_info = get_tx_info().unbox();
                self.emit(GasFeePaid { 
                    user, 
                    gas_used, 
                    fee_amount,
                    transaction_hash: tx_info.transaction_hash 
                });
                
                true
            } else {
                false
            }
        }

        // Estimate gas cost for a transaction
        fn estimate_gas_cost(self: @ContractState, estimated_gas: u256) -> u256 {
            self.calculate_gas_fee(estimated_gas)
        }

        // Check user's gas allowance
        fn get_gas_allowance(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_gas_allowances.read(user)
        }

        // Get collected fees
        fn get_collected_fees(self: @ContractState) -> u256 {
            self.collected_fees.read()
        }

        // Withdraw collected fees (owner only)
        fn withdraw_fees(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            let available_fees = self.collected_fees.read();
            assert(amount <= available_fees, 'Insufficient fees to withdraw');
            
            let hancoin_token = self.hancoin_token.read();
            self._transfer_to_address(to, amount, hancoin_token);
            
            self.collected_fees.write(available_fees - amount);
            self.emit(FeesWithdrawn { to, amount });
        }

        // Update base gas fee (owner only)
        fn set_base_gas_fee(ref self: ContractState, new_fee: u256) {
            self.ownable.assert_only_owner();
            self.base_gas_fee.write(new_fee);
        }

        // Update fee multiplier (owner only)
        fn set_fee_multiplier(ref self: ContractState, new_multiplier: u256) {
            self.ownable.assert_only_owner();
            self.fee_multiplier.write(new_multiplier);
        }

        // Get current settings
        fn get_base_gas_fee(self: @ContractState) -> u256 {
            self.base_gas_fee.read()
        }

        fn get_fee_multiplier(self: @ContractState) -> u256 {
            self.fee_multiplier.read()
        }

        fn get_hancoin_token(self: @ContractState) -> ContractAddress {
            self.hancoin_token.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _transfer_from_user(
            ref self: ContractState, 
            user: ContractAddress, 
            amount: u256,
            token_address: ContractAddress
        ) -> bool {
            // This would call the HNXZ token contract's transfer_from function
            // For now, we'll simulate this with a simple check
            // In production, you'd use the actual token contract interface
            true // Placeholder - implement actual token transfer logic
        }

        fn _transfer_to_address(
            ref self: ContractState,
            to: ContractAddress,
            amount: u256,
            token_address: ContractAddress
        ) {
            // Transfer tokens from this contract to specified address
            // Implement actual token transfer logic here
        }
    }

    #[starknet::interface]
    trait IPaymaster<TContractState> {
        fn set_gas_allowance(ref self: TContractState, user: ContractAddress, allowance: u256);
        fn calculate_gas_fee(self: @TContractState, gas_used: u256) -> u256;
        fn pay_gas_fee(ref self: TContractState, user: ContractAddress, gas_used: u256) -> bool;
        fn estimate_gas_cost(self: @TContractState, estimated_gas: u256) -> u256;
        fn get_gas_allowance(self: @TContractState, user: ContractAddress) -> u256;
        fn get_collected_fees(self: @TContractState) -> u256;
        fn withdraw_fees(ref self: TContractState, to: ContractAddress, amount: u256);
        fn set_base_gas_fee(ref self: TContractState, new_fee: u256);
        fn set_fee_multiplier(ref self: TContractState, new_multiplier: u256);
        fn get_base_gas_fee(self: @TContractState) -> u256;
        fn get_fee_multiplier(self: @TContractState) -> u256;
        fn get_hancoin_token(self: @TContractState) -> ContractAddress;
    }
}