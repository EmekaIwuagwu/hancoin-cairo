// SPDX-License-Identifier: MIT
// Swap Contract - DEX Integration for HNXZ token swaps

#[starknet::contract]
mod SwapContract {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[derive(Drop, Serde, starknet::Store)]
    struct SwapPair {
        token_a: ContractAddress,
        token_b: ContractAddress,
        liquidity_pool: ContractAddress,
        fee_rate: u256, // Fee rate in basis points
        is_active: bool,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct SwapTransaction {
        id: u256,
        user: ContractAddress,
        token_in: ContractAddress,
        token_out: ContractAddress,
        amount_in: u256,
        amount_out: u256,
        timestamp: u64,
        swap_rate: u256, // Rate at time of swap
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        hancoin_token: ContractAddress,
        // DEX Router addresses
        jediswap_router: ContractAddress,
        tenk_swap_router: ContractAddress,
        myswap_router: ContractAddress,
        // Supported tokens
        usdt_token: ContractAddress,
        usdc_token: ContractAddress,
        wbtc_token: ContractAddress,
        weth_token: ContractAddress,
        wbnb_token: ContractAddress,
        // Swap pairs and settings
        swap_pairs: LegacyMap::<(ContractAddress, ContractAddress), SwapPair>,
        next_tx_id: u256,
        swap_transactions: LegacyMap::<u256, SwapTransaction>,
        user_swap_history: LegacyMap::<ContractAddress, Array<u256>>,
        // Swap settings
        max_slippage: u256, // Maximum allowed slippage in basis points
        swap_fee: u256, // Protocol swap fee in basis points
        min_swap_amount: u256,
        max_swap_amount: u256,
        // Statistics
        total_swaps: u256,
        total_volume: u256,
        total_fees_collected: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        SwapExecuted: SwapExecuted,
        LiquidityAdded: LiquidityAdded,
        LiquidityRemoved: LiquidityRemoved,
        SwapPairUpdated: SwapPairUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct SwapExecuted {
        tx_id: u256,
        user: ContractAddress,
        token_in: ContractAddress,
        token_out: ContractAddress,
        amount_in: u256,
        amount_out: u256,
        fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LiquidityAdded {
        user: ContractAddress,
        token_a: ContractAddress,
        token_b: ContractAddress,
        amount_a: u256,
        amount_b: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LiquidityRemoved {
        user: ContractAddress,
        token_a: ContractAddress,
        token_b: ContractAddress,
        amount_a: u256,
        amount_b: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SwapPairUpdated {
        token_a: ContractAddress,
        token_b: ContractAddress,
        is_active: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        hancoin_token: ContractAddress,
        jediswap_router: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.hancoin_token.write(hancoin_token);
        self.jediswap_router.write(jediswap_router);
        self.next_tx_id.write(1);
        self.max_slippage.write(300); // 3% max slippage
        self.swap_fee.write(30); // 0.3% protocol fee
        self.min_swap_amount.write(1 * 1000000000000000000); // 1 token minimum
        self.max_swap_amount.write(1000000 * 1000000000000000000); // 1M tokens maximum
        self.total_swaps.write(0);
        self.total_volume.write(0);
        self.total_fees_collected.write(0);
    }

    #[abi(embed_v0)]
    impl SwapContractImpl of super::ISwapContract<ContractState> {
        // Get quote for HNXZ to other token swap
        fn get_swap_quote(
            self: @ContractState,
            token_in: ContractAddress,
            token_out: ContractAddress,
            amount_in: u256
        ) -> u256 {
            assert(amount_in > 0, 'Amount must be positive');
            
            // Check if this is a supported pair
            let pair = self.swap_pairs.read((token_in, token_out));
            if !pair.is_active {
                // Try reverse pair
                let reverse_pair = self.swap_pairs.read((token_out, token_in));
                assert(reverse_pair.is_active, 'Pair not supported');
            }
            
            // Simulate getting quote from DEX
            // In production, this would call the actual DEX router
            self._simulate_swap_quote(token_in, token_out, amount_in)
        }

        // Execute swap: HNXZ <-> Other tokens
        fn execute_swap(
            ref self: ContractState,
            token_in: ContractAddress,
            token_out: ContractAddress,
            amount_in: u256,
            min_amount_out: u256,
            deadline: u64
        ) -> u256 {
            let user = get_caller_address();
            let current_time = get_block_timestamp();
            
            // Validate parameters
            assert(current_time <= deadline, 'Deadline exceeded');
            assert(amount_in >= self.min_swap_amount.read(), 'Amount below minimum');
            assert(amount_in <= self.max_swap_amount.read(), 'Amount above maximum');
            assert(token_in != token_out, 'Cannot swap same token');
            
            // Check supported pair
            let pair = self.swap_pairs.read((token_in, token_out));
            let reverse_pair = self.swap_pairs.read((token_out, token_in));
            assert(pair.is_active || reverse_pair.is_active, 'Pair not supported');
            
            // Get swap quote
            let quote = self.get_swap_quote(token_in, token_out, amount_in);
            assert(quote >= min_amount_out, 'Slippage too high');
            
            // Calculate protocol fee
            let protocol_fee = (amount_in * self.swap_fee.read()) / 10000;
            let net_amount_in = amount_in - protocol_fee;
            
            // Execute the actual swap
            let amount_out = self._execute_dex_swap(
                user, 
                token_in, 
                token_out, 
                net_amount_in, 
                min_amount_out
            );
            
            // Record transaction
            let tx_id = self.next_tx_id.read();
            let swap_tx = SwapTransaction {
                id: tx_id,
                user,
                token_in,
                token_out,
                amount_in,
                amount_out,
                timestamp: current_time,
                swap_rate: (amount_out * 1000000000000000000) / amount_in, // Rate with 18 decimals
            };
            
            self.swap_transactions.write(tx_id, swap_tx);
            self.next_tx_id.write(tx_id + 1);
            
            // Update statistics
            let total_swaps = self.total_swaps.read();
            self.total_swaps.write(total_swaps + 1);
            
            let total_volume = self.total_volume.read();
            self.total_volume.write(total_volume + amount_in);
            
            let total_fees = self.total_fees_collected.read();
            self.total_fees_collected.write(total_fees + protocol_fee);
            
            self.emit(SwapExecuted { 
                tx_id, 
                user, 
                token_in, 
                token_out, 
                amount_in, 
                amount_out, 
                fee: protocol_fee 
            });
            
            amount_out
        }

        // Swap HNXZ to USDT
        fn swap_hnxz_to_usdt(
            ref self: ContractState, 
            amount_in: u256, 
            min_amount_out: u256
        ) -> u256 {
            let deadline = get_block_timestamp() + 600; // 10 minutes deadline
            self.execute_swap(
                self.hancoin_token.read(),
                self.usdt_token.read(),
                amount_in,
                min_amount_out,
                deadline
            )
        }

        // Swap USDT to HNXZ
        fn swap_usdt_to_hnxz(
            ref self: ContractState, 
            amount_in: u256, 
            min_amount_out: u256
        ) -> u256 {
            let deadline = get_block_timestamp() + 600;
            self.execute_swap(
                self.usdt_token.read(),
                self.hancoin_token.read(),
                amount_in,
                min_amount_out,
                deadline
            )
        }

        // Swap HNXZ to USDC
        fn swap_hnxz_to_usdc(
            ref self: ContractState, 
            amount_in: u256, 
            min_amount_out: u256
        ) -> u256 {
            let deadline = get_block_timestamp() + 600;
            self.execute_swap(
                self.hancoin_token.read(),
                self.usdc_token.read(),
                amount_in,
                min_amount_out,
                deadline
            )
        }

        // Swap HNXZ to WETH
        fn swap_hnxz_to_weth(
            ref self: ContractState, 
            amount_in: u256, 
            min_amount_out: u256
        ) -> u256 {
            let deadline = get_block_timestamp() + 600;
            self.execute_swap(
                self.hancoin_token.read(),
                self.weth_token.read(),
                amount_in,
                min_amount_out,
                deadline
            )
        }

        // Swap HNXZ to WBTC
        fn swap_hnxz_to_wbtc(
            ref self: ContractState, 
            amount_in: u256, 
            min_amount_out: u256
        ) -> u256 {
            let deadline = get_block_timestamp() + 600;
            self.execute_swap(
                self.hancoin_token.read(),
                self.wbtc_token.read(),
                amount_in,
                min_amount_out,
                deadline
            )
        }

        // Add liquidity to HNXZ pairs
        fn add_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a: u256,
            amount_b: u256,
            min_liquidity: u256
        ) -> u256 {
            let user = get_caller_address();
            
            // Validate that one of the tokens is HNXZ
            let hancoin = self.hancoin_token.read();
            assert(token_a == hancoin || token_b == hancoin, 'Must include HNXZ');
            
            // Transfer tokens from user
            self._transfer_from_user(user, token_a, amount_a);
            self._transfer_from_user(user, token_b, amount_b);
            
            // Add liquidity to DEX (simulated)
            let liquidity_tokens = self._add_dex_liquidity(
                token_a, 
                token_b, 
                amount_a, 
                amount_b
            );
            
            assert(liquidity_tokens >= min_liquidity, 'Insufficient liquidity');
            
            self.emit(LiquidityAdded { user, token_a, token_b, amount_a, amount_b });
            
            liquidity_tokens
        }

        // Remove liquidity from HNXZ pairs
        fn remove_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity_tokens: u256,
            min_amount_a: u256,
            min_amount_b: u256
        ) -> (u256, u256) {
            let user = get_caller_address();
            
            // Remove liquidity from DEX (simulated)
            let (amount_a, amount_b) = self._remove_dex_liquidity(
                token_a, 
                token_b, 
                liquidity_tokens
            );
            
            assert(amount_a >= min_amount_a, 'Insufficient amount A');
            assert(amount_b >= min_amount_b, 'Insufficient amount B');
            
            // Transfer tokens back to user
            self._transfer_to_user(user, token_a, amount_a);
            self._transfer_to_user(user, token_b, amount_b);
            
            self.emit(LiquidityRemoved { user, token_a, token_b, amount_a, amount_b });
            
            (amount_a, amount_b)
        }

        // Get swap transaction details
        fn get_swap_transaction(self: @ContractState, tx_id: u256) -> SwapTransaction {
            self.swap_transactions.read(tx_id)
        }

        // Get user's swap history count
        fn get_user_swap_count(self: @ContractState, user: ContractAddress) -> u256 {
            // Simplified implementation - count user's swaps
            let mut count = 0;
            let total_swaps = self.next_tx_id.read() - 1;
            let mut i = 1;
            
            loop {
                if i > total_swaps {
                    break;
                }
                let swap_tx = self.swap_transactions.read(i);
                if swap_tx.user == user {
                    count += 1;
                }
                i += 1;
            };
            
            count
        }

        // Get contract statistics
        fn get_total_swaps(self: @ContractState) -> u256 {
            self.total_swaps.read()
        }

        fn get_total_volume(self: @ContractState) -> u256 {
            self.total_volume.read()
        }

        fn get_total_fees_collected(self: @ContractState) -> u256 {
            self.total_fees_collected.read()
        }

        // Admin functions
        fn set_supported_token(
            ref self: ContractState, 
            token_type: felt252, 
            token_address: ContractAddress
        ) {
            self.ownable.assert_only_owner();
            
            if token_type == 'USDT' {
                self.usdt_token.write(token_address);
            } else if token_type == 'USDC' {
                self.usdc_token.write(token_address);
            } else if token_type == 'WBTC' {
                self.wbtc_token.write(token_address);
            } else if token_type == 'WETH' {
                self.weth_token.write(token_address);
            } else if token_type == 'WBNB' {
                self.wbnb_token.write(token_address);
            }
        }

        fn set_swap_pair(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity_pool: ContractAddress,
            fee_rate: u256,
            is_active: bool
        ) {
            self.ownable.assert_only_owner();
            
            let pair = SwapPair {
                token_a,
                token_b,
                liquidity_pool,
                fee_rate,
                is_active,
            };
            
            self.swap_pairs.write((token_a, token_b), pair);
            
            self.emit(SwapPairUpdated { token_a, token_b, is_active });
        }

        fn set_dex_router(
            ref self: ContractState, 
            router_type: felt252, 
            router_address: ContractAddress
        ) {
            self.ownable.assert_only_owner();
            
            if router_type == 'JEDI' {
                self.jediswap_router.write(router_address);
            } else if router_type == '10K' {
                self.tenk_swap_router.write(router_address);
            } else if router_type == 'MYSWAP' {
                self.myswap_router.write(router_address);
            }
        }

        fn set_swap_fee(ref self: ContractState, new_fee: u256) {
            self.ownable.assert_only_owner();
            assert(new_fee <= 1000, 'Fee too high'); // Max 10%
            self.swap_fee.write(new_fee);
        }

        fn set_max_slippage(ref self: ContractState, new_slippage: u256) {
            self.ownable.assert_only_owner();
            assert(new_slippage <= 2000, 'Slippage too high'); // Max 20%
            self.max_slippage.write(new_slippage);
        }

        // Get current settings
        fn get_swap_fee(self: @ContractState) -> u256 {
            self.swap_fee.read()
        }

        fn get_max_slippage(self: @ContractState) -> u256 {
            self.max_slippage.read()
        }

        fn get_supported_token(self: @ContractState, token_type: felt252) -> ContractAddress {
            if token_type == 'USDT' {
                self.usdt_token.read()
            } else if token_type == 'USDC' {
                self.usdc_token.read()
            } else if token_type == 'WBTC' {
                self.wbtc_token.read()
            } else if token_type == 'WETH' {
                self.weth_token.read()
            } else if token_type == 'WBNB' {
                self.wbnb_token.read()
            } else {
                starknet::contract_address_const::<0>()
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _simulate_swap_quote(
            self: @ContractState,
            token_in: ContractAddress,
            token_out: ContractAddress,
            amount_in: u256
        ) -> u256 {
            // Simplified simulation - in production, call actual DEX
            // Using rough exchange rates for simulation
            let hancoin = self.hancoin_token.read();
            
            if token_in == hancoin {
                // HNXZ to other token
                if token_out == self.usdt_token.read() {
                    (amount_in * 50) / 100 // 1 HNXZ = 0.5 USDT
                } else if token_out == self.usdc_token.read() {
                    (amount_in * 50) / 100 // 1 HNXZ = 0.5 USDC
                } else if token_out == self.weth_token.read() {
                    (amount_in * 15) / 100000 // 1 HNXZ = 0.00015 ETH
                } else if token_out == self.wbtc_token.read() {
                    (amount_in * 5) / 1000000 // 1 HNXZ = 0.000005 BTC
                } else {
                    amount_in / 2 // Default rate
                }
            } else {
                // Other token to HNXZ
                if token_in == self.usdt_token.read() {
                    (amount_in * 200) / 100 // 1 USDT = 2 HNXZ
                } else if token_in == self.usdc_token.read() {
                    (amount_in * 200) / 100 // 1 USDC = 2 HNXZ
                } else if token_in == self.weth_token.read() {
                    (amount_in * 6667 * 1000000000000000000) / 1000000000000000000 // 1 ETH = 6667 HNXZ
                } else if token_in == self.wbtc_token.read() {
                    (amount_in * 200000 * 1000000000000000000) / 1000000000000000000 // 1 BTC = 200k HNXZ
                } else {
                    amount_in * 2 // Default rate
                }
            }
        }

        fn _execute_dex_swap(
            ref self: ContractState,
            user: ContractAddress,
            token_in: ContractAddress,
            token_out: ContractAddress,
            amount_in: u256,
            min_amount_out: u256
        ) -> u256 {
            // Transfer input token from user
            self._transfer_from_user(user, token_in, amount_in);
            
            // Simulate DEX swap - in production, call actual router
            let amount_out = self._simulate_swap_quote(token_in, token_out, amount_in);
            
            // Apply slippage (simulate market conditions)
            let slippage_factor = 9950; // 0.5% slippage
            let final_amount = (amount_out * slippage_factor) / 10000;
            
            // Transfer output token to user
            self._transfer_to_user(user, token_out, final_amount);
            
            final_amount
        }

        fn _add_dex_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a: u256,
            amount_b: u256
        ) -> u256 {
            // Simulate adding liquidity - return LP tokens
            // In production, call actual DEX router
            let sqrt_product = self._sqrt(amount_a * amount_b);
            sqrt_product
        }

        fn _remove_dex_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity_tokens: u256
        ) -> (u256, u256) {
            // Simulate removing liquidity
            // In production, call actual DEX router
            let amount_a = liquidity_tokens / 2;
            let amount_b = liquidity_tokens / 2;
            (amount_a, amount_b)
        }

        fn _transfer_from_user(
            ref self: ContractState, 
            user: ContractAddress, 
            token: ContractAddress, 
            amount: u256
        ) {
            // Transfer tokens from user to this contract
            // In production, call token.transfer_from(user, get_contract_address(), amount)
        }

        fn _transfer_to_user(
            ref self: ContractState, 
            user: ContractAddress, 
            token: ContractAddress, 
            amount: u256
        ) {
            // Transfer tokens from this contract to user
            // In production, call token.transfer(user, amount)
        }

        fn _sqrt(self: @ContractState, x: u256) -> u256 {
            if x == 0 {
                return 0;
            }
            
            let mut z = (x + 1) / 2;
            let mut y = x;
            
            loop {
                if z >= y {
                    break;
                }
                y = z;
                z = (x / z + z) / 2;
            };
            
            y
        }
    }

    #[starknet::interface]
    trait ISwapContract<TContractState> {
        fn get_swap_quote(
            self: @TContractState,
            token_in: ContractAddress,
            token_out: ContractAddress,
            amount_in: u256
        ) -> u256;
        fn execute_swap(
            ref self: TContractState,
            token_in: ContractAddress,
            token_out: ContractAddress,
            amount_in: u256,
            min_amount_out: u256,
            deadline: u64
        ) -> u256;
        fn swap_hnxz_to_usdt(ref self: TContractState, amount_in: u256, min_amount_out: u256) -> u256;
        fn swap_usdt_to_hnxz(ref self: TContractState, amount_in: u256, min_amount_out: u256) -> u256;
        fn swap_hnxz_to_usdc(ref self: TContractState, amount_in: u256, min_amount_out: u256) -> u256;
        fn swap_hnxz_to_weth(ref self: TContractState, amount_in: u256, min_amount_out: u256) -> u256;
        fn swap_hnxz_to_wbtc(ref self: TContractState, amount_in: u256, min_amount_out: u256) -> u256;
        fn add_liquidity(
            ref self: TContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a: u256,
            amount_b: u256,
            min_liquidity: u256
        ) -> u256;
        fn remove_liquidity(
            ref self: TContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity_tokens: u256,
            min_amount_a: u256,
            min_amount_b: u256
        ) -> (u256, u256);
        fn get_swap_transaction(self: @TContractState, tx_id: u256) -> SwapTransaction;
        fn get_user_swap_count(self: @TContractState, user: ContractAddress) -> u256;
        fn get_total_swaps(self: @TContractState) -> u256;
        fn get_total_volume(self: @TContractState) -> u256;
        fn get_total_fees_collected(self: @TContractState) -> u256;
        fn set_supported_token(ref self: TContractState, token_type: felt252, token_address: ContractAddress);
        fn set_swap_pair(
            ref self: TContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity_pool: ContractAddress,
            fee_rate: u256,
            is_active: bool
        );
        fn set_dex_router(ref self: TContractState, router_type: felt252, router_address: ContractAddress);
        fn set_swap_fee(ref self: TContractState, new_fee: u256);
        fn set_max_slippage(ref self: TContractState, new_slippage: u256);
        fn get_swap_fee(self: @TContractState) -> u256;
        fn get_max_slippage(self: @TContractState) -> u256;
        fn get_supported_token(self: @TContractState, token_type: felt252) -> ContractAddress;
    }
}