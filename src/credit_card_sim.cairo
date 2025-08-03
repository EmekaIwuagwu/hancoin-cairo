// SPDX-License-Identifier: MIT
// Credit Card Simulation Contract - Mock Web2 to Web3 Bridge for HNXZ Purchase

#[starknet::contract]
mod CreditCardSimulator {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[derive(Drop, Serde, starknet::Store)]
    struct PaymentRequest {
        id: u256,
        user: ContractAddress,
        fiat_amount: u256, // Amount in cents (e.g., $100.00 = 10000)
        fiat_currency: felt252, // 'USD', 'EUR', 'GBP', etc.
        hnxz_amount: u256, // Equivalent HNXZ tokens
        card_last_four: felt252, // Last 4 digits of card (for display)
        status: PaymentStatus,
        created_at: u64,
        processed_at: u64,
        transaction_ref: felt252, // Mock transaction reference
        exchange_rate: u256, // Fiat to HNXZ rate at time of transaction
    }

    #[derive(Drop, Serde, starknet::Store)]
    enum PaymentStatus {
        Pending,     // Payment initiated, awaiting processing
        Processing,  // Being processed by "payment processor"
        Completed,   // Payment successful, HNXZ credited
        Failed,      // Payment failed
        Cancelled,   // Payment cancelled by user
        Refunded,    // Payment refunded
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct ExchangeRate {
        currency: felt252,
        rate: u256, // Rate in basis points (e.g., 20000 = $0.20 per HNXZ)
        last_updated: u64,
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        hancoin_token: ContractAddress,
        next_payment_id: u256,
        payment_requests: LegacyMap::<u256, PaymentRequest>,
        user_payments: LegacyMap::<ContractAddress, Array<u256>>,
        // Exchange rates for different fiat currencies
        exchange_rates: LegacyMap::<felt252, ExchangeRate>,
        // Payment settings
        min_purchase_amount: u256, // Minimum fiat amount in cents
        max_purchase_amount: u256, // Maximum fiat amount in cents
        processing_fee_rate: u256, // Processing fee in basis points
        // Mock payment processor settings
        success_rate: u256, // Simulated success rate (basis points)
        processing_delay: u64, // Simulated processing delay in seconds
        // Statistics
        total_payments: u256,
        total_fiat_processed: u256,
        total_hnxz_issued: u256,
        total_fees_collected: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        PaymentInitiated: PaymentInitiated,
        PaymentProcessed: PaymentProcessed,
        PaymentCompleted: PaymentCompleted,
        PaymentFailed: PaymentFailed,
        PaymentRefunded: PaymentRefunded,
        ExchangeRateUpdated: ExchangeRateUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentInitiated {
        payment_id: u256,
        user: ContractAddress,
        fiat_amount: u256,
        fiat_currency: felt252,
        hnxz_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentProcessed {
        payment_id: u256,
        user: ContractAddress,
        transaction_ref: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentCompleted {
        payment_id: u256,
        user: ContractAddress,
        hnxz_amount: u256,
        fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentFailed {
        payment_id: u256,
        user: ContractAddress,
        reason: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentRefunded {
        payment_id: u256,
        user: ContractAddress,
        refund_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ExchangeRateUpdated {
        currency: felt252,
        old_rate: u256,
        new_rate: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        hancoin_token: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.hancoin_token.write(hancoin_token);
        self.next_payment_id.write(1);
        self.min_purchase_amount.write(1000); // $10.00 minimum
        self.max_purchase_amount.write(10000000); // $100,000 maximum
        self.processing_fee_rate.write(300); // 3% processing fee
        self.success_rate.write(9500); // 95% success rate simulation
        self.processing_delay.write(30); // 30 seconds processing delay
        self.total_payments.write(0);
        self.total_fiat_processed.write(0);
        self.total_hnxz_issued.write(0);
        self.total_fees_collected.write(0);
        
        // Initialize default exchange rates
        self._set_default_exchange_rates();
    }

    #[abi(embed_v0)]
    impl CreditCardSimulatorImpl of super::ICreditCardSimulator<ContractState> {
        // Initiate credit card payment for HNXZ
        fn initiate_payment(
            ref self: ContractState,
            fiat_amount: u256, // Amount in cents
            fiat_currency: felt252,
            card_last_four: felt252
        ) -> u256 {
            let user = get_caller_address();
            let current_time = get_block_timestamp();
            
            // Validate payment amount
            assert(fiat_amount >= self.min_purchase_amount.read(), 'Amount below minimum');
            assert(fiat_amount <= self.max_purchase_amount.read(), 'Amount above maximum');
            
            // Get current exchange rate
            let exchange_rate = self.exchange_rates.read(fiat_currency);
            assert(exchange_rate.rate > 0, 'Currency not supported');
            
            // Calculate HNXZ amount (convert fiat cents to HNXZ with 18 decimals)
            let hnxz_amount = self._calculate_hnxz_amount(fiat_amount, exchange_rate.rate);
            
            // Create payment request
            let payment_id = self.next_payment_id.read();
            let payment_request = PaymentRequest {
                id: payment_id,
                user,
                fiat_amount,
                fiat_currency,
                hnxz_amount,
                card_last_four,
                status: PaymentStatus::Pending,
                created_at: current_time,
                processed_at: 0,
                transaction_ref: 0,
                exchange_rate: exchange_rate.rate,
            };
            
            // Store payment request
            self.payment_requests.write(payment_id, payment_request);
            self.next_payment_id.write(payment_id + 1);
            
            self.emit(PaymentInitiated { 
                payment_id, 
                user, 
                fiat_amount, 
                fiat_currency, 
                hnxz_amount 
            });
            
            payment_id
        }

        // Process pending payment (simulates payment processor)
        fn process_payment(ref self: ContractState, payment_id: u256) -> bool {
            let mut payment = self.payment_requests.read(payment_id);
            
            assert(payment.status == PaymentStatus::Pending, 'Payment not pending');
            
            // Update status to processing
            payment.status = PaymentStatus::Processing;
            payment.processed_at = get_block_timestamp();
            payment.transaction_ref = self._generate_transaction_ref(payment_id);
            self.payment_requests.write(payment_id, payment);
            
            self.emit(PaymentProcessed { 
                payment_id, 
                user: payment.user, 
                transaction_ref: payment.transaction_ref 
            });
            
            // Simulate processing delay and success/failure
            let success = self._simulate_payment_processing(payment_id);
            
            if success {
                self._complete_payment(payment_id);
                true
            } else {
                self._fail_payment(payment_id, 'CARD_DECLINED');
                false
            }
        }

        // Complete successful payment
        fn _complete_payment(ref self: ContractState, payment_id: u256) {
            let mut payment = self.payment_requests.read(payment_id);
            
            // Calculate processing fee
            let fee = (payment.hnxz_amount * self.processing_fee_rate.read()) / 10000;
            let net_hnxz = payment.hnxz_amount - fee;
            
            // Mint HNXZ tokens to user (simulate credit to wallet)
            self._mint_hnxz_to_user(payment.user, net_hnxz);
            
            // Update payment status
            payment.status = PaymentStatus::Completed;
            self.payment_requests.write(payment_id, payment);
            
            // Update statistics
            let total_payments = self.total_payments.read();
            self.total_payments.write(total_payments + 1);
            
            let total_fiat = self.total_fiat_processed.read();
            self.total_fiat_processed.write(total_fiat + payment.fiat_amount);
            
            let total_hnxz = self.total_hnxz_issued.read();
            self.total_hnxz_issued.write(total_hnxz + net_hnxz);
            
            let total_fees = self.total_fees_collected.read();
            self.total_fees_collected.write(total_fees + fee);
            
            self.emit(PaymentCompleted { 
                payment_id, 
                user: payment.user, 
                hnxz_amount: net_hnxz, 
                fee 
            });
        }

        // Handle failed payment
        fn _fail_payment(ref self: ContractState, payment_id: u256, reason: felt252) {
            let mut payment = self.payment_requests.read(payment_id);
            
            payment.status = PaymentStatus::Failed;
            self.payment_requests.write(payment_id, payment);
            
            self.emit(PaymentFailed { payment_id, user: payment.user, reason });
        }

        // Get payment details
        fn get_payment(self: @ContractState, payment_id: u256) -> PaymentRequest {
            self.payment_requests.read(payment_id)
        }

        // Get payment status
        fn get_payment_status(self: @ContractState, payment_id: u256) -> PaymentStatus {
            let payment = self.payment_requests.read(payment_id);
            payment.status
        }

        // Cancel pending payment
        fn cancel_payment(ref self: ContractState, payment_id: u256) {
            let mut payment = self.payment_requests.read(payment_id);
            let caller = get_caller_address();
            
            assert(payment.user == caller, 'Not payment owner');
            assert(payment.status == PaymentStatus::Pending, 'Cannot cancel payment');
            
            payment.status = PaymentStatus::Cancelled;
            self.payment_requests.write(payment_id, payment);
        }

        // Refund completed payment (admin only)
        fn refund_payment(ref self: ContractState, payment_id: u256) {
            self.ownable.assert_only_owner();
            let mut payment = self.payment_requests.read(payment_id);
            
            assert(payment.status == PaymentStatus::Completed, 'Payment not completed');
            
            // Calculate refund amount (net HNXZ received)
            let fee = (payment.hnxz_amount * self.processing_fee_rate.read()) / 10000;
            let refund_amount = payment.hnxz_amount - fee;
            
            // Burn HNXZ from user (reverse the credit)
            self._burn_hnxz_from_user(payment.user, refund_amount);
            
            // Update payment status
            payment.status = PaymentStatus::Refunded;
            self.payment_requests.write(payment_id, payment);
            
            // Update statistics
            let total_hnxz = self.total_hnxz_issued.read();
            self.total_hnxz_issued.write(total_hnxz - refund_amount);
            
            self.emit(PaymentRefunded { 
                payment_id, 
                user: payment.user, 
                refund_amount 
            });
        }

        // Calculate HNXZ amount for given fiat
        fn calculate_hnxz_amount(
            self: @ContractState, 
            fiat_amount: u256, 
            fiat_currency: felt252
        ) -> u256 {
            let exchange_rate = self.exchange_rates.read(fiat_currency);
            assert(exchange_rate.rate > 0, 'Currency not supported');
            
            self._calculate_hnxz_amount(fiat_amount, exchange_rate.rate)
        }

        // Get exchange rate for currency
        fn get_exchange_rate(self: @ContractState, currency: felt252) -> ExchangeRate {
            self.exchange_rates.read(currency)
        }

        // Get user payment history count
        fn get_user_payment_count(self: @ContractState, user: ContractAddress) -> u256 {
            // Simplified implementation - count user's payments
            let mut count = 0;
            let total_payments = self.next_payment_id.read() - 1;
            let mut i = 1;
            
            loop {
                if i > total_payments {
                    break;
                }
                let payment = self.payment_requests.read(i);
                if payment.user == user {
                    count += 1;
                }
                i += 1;
            };
            
            count
        }

        // Get contract statistics
        fn get_total_payments(self: @ContractState) -> u256 {
            self.total_payments.read()
        }

        fn get_total_fiat_processed(self: @ContractState) -> u256 {
            self.total_fiat_processed.read()
        }

        fn get_total_hnxz_issued(self: @ContractState) -> u256 {
            self.total_hnxz_issued.read()
        }

        fn get_total_fees_collected(self: @ContractState) -> u256 {
            self.total_fees_collected.read()
        }

        // Admin functions
        fn update_exchange_rate(
            ref self: ContractState, 
            currency: felt252, 
            new_rate: u256
        ) {
            self.ownable.assert_only_owner();
            
            let old_rate = self.exchange_rates.read(currency);
            let updated_rate = ExchangeRate {
                currency,
                rate: new_rate,
                last_updated: get_block_timestamp(),
            };
            
            self.exchange_rates.write(currency, updated_rate);
            
            self.emit(ExchangeRateUpdated { 
                currency, 
                old_rate: old_rate.rate, 
                new_rate 
            });
        }

        fn set_processing_fee_rate(ref self: ContractState, new_rate: u256) {
            self.ownable.assert_only_owner();
            assert(new_rate <= 1000, 'Fee rate too high'); // Max 10%
            self.processing_fee_rate.write(new_rate);
        }

        fn set_payment_limits(
            ref self: ContractState, 
            min_amount: u256, 
            max_amount: u256
        ) {
            self.ownable.assert_only_owner();
            assert(min_amount < max_amount, 'Invalid limits');
            self.min_purchase_amount.write(min_amount);
            self.max_purchase_amount.write(max_amount);
        }

        fn set_success_rate(ref self: ContractState, new_rate: u256) {
            self.ownable.assert_only_owner();
            assert(new_rate <= 10000, 'Invalid success rate');
            self.success_rate.write(new_rate);
        }

        // Get current settings
        fn get_processing_fee_rate(self: @ContractState) -> u256 {
            self.processing_fee_rate.read()
        }

        fn get_payment_limits(self: @ContractState) -> (u256, u256) {
            (self.min_purchase_amount.read(), self.max_purchase_amount.read())
        }

        fn get_success_rate(self: @ContractState) -> u256 {
            self.success_rate.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _set_default_exchange_rates(ref self: ContractState) {
            let current_time = get_block_timestamp();
            
            // Set default exchange rates (in cents per HNXZ)
            // E.g., if 1 HNXZ = $0.50, rate = 50
            let usd_rate = ExchangeRate {
                currency: 'USD',
                rate: 50, // $0.50 per HNXZ
                last_updated: current_time,
            };
            self.exchange_rates.write('USD', usd_rate);
            
            let eur_rate = ExchangeRate {
                currency: 'EUR',
                rate: 45, // €0.45 per HNXZ
                last_updated: current_time,
            };
            self.exchange_rates.write('EUR', eur_rate);
            
            let gbp_rate = ExchangeRate {
                currency: 'GBP',
                rate: 40, // £0.40 per HNXZ
                last_updated: current_time,
            };
            self.exchange_rates.write('GBP', gbp_rate);
        }

        fn _calculate_hnxz_amount(
            self: @ContractState, 
            fiat_amount: u256, 
            exchange_rate: u256
        ) -> u256 {
            // Convert fiat cents to HNXZ tokens with 18 decimals
            // fiat_amount is in cents, exchange_rate is cents per HNXZ
            (fiat_amount * 1000000000000000000) / exchange_rate
        }

        fn _generate_transaction_ref(self: @ContractState, payment_id: u256) -> felt252 {
            // Generate a mock transaction reference
            let timestamp = get_block_timestamp();
            let ref_num = (payment_id * 1000) + (timestamp % 1000);
            ref_num.try_into().unwrap()
        }

        fn _simulate_payment_processing(self: @ContractState, payment_id: u256) -> bool {
            // Simple simulation based on success rate
            let success_rate = self.success_rate.read();
            let random_factor = (payment_id * 7919) % 10000; // Pseudo-random
            random_factor < success_rate
        }

        fn _mint_hnxz_to_user(ref self: ContractState, user: ContractAddress, amount: u256) {
            // In production, call the HNXZ token contract to mint tokens
            // For now, this is a placeholder for the minting logic
        }

        fn _burn_hnxz_from_user(ref self: ContractState, user: ContractAddress, amount: u256) {
            // In production, call the HNXZ token contract to burn tokens
            // For now, this is a placeholder for the burning logic
        }
    }

    #[starknet::interface]
    trait ICreditCardSimulator<TContractState> {
        fn initiate_payment(
            ref self: TContractState,
            fiat_amount: u256,
            fiat_currency: felt252,
            card_last_four: felt252
        ) -> u256;
        fn process_payment(ref self: TContractState, payment_id: u256) -> bool;
        fn get_payment(self: @TContractState, payment_id: u256) -> PaymentRequest;
        fn get_payment_status(self: @TContractState, payment_id: u256) -> PaymentStatus;
        fn cancel_payment(ref self: TContractState, payment_id: u256);
        fn refund_payment(ref self: TContractState, payment_id: u256);
        fn calculate_hnxz_amount(
            self: @TContractState, 
            fiat_amount: u256, 
            fiat_currency: felt252
        ) -> u256;
        fn get_exchange_rate(self: @TContractState, currency: felt252) -> ExchangeRate;
        fn get_user_payment_count(self: @TContractState, user: ContractAddress) -> u256;
        fn get_total_payments(self: @TContractState) -> u256;
        fn get_total_fiat_processed(self: @TContractState) -> u256;
        fn get_total_hnxz_issued(self: @TContractState) -> u256;
        fn get_total_fees_collected(self: @TContractState) -> u256;
        fn update_exchange_rate(ref self: TContractState, currency: felt252, new_rate: u256);
        fn set_processing_fee_rate(ref self: TContractState, new_rate: u256);
        fn set_payment_limits(ref self: TContractState, min_amount: u256, max_amount: u256);
        fn set_success_rate(ref self: TContractState, new_rate: u256);
        fn get_processing_fee_rate(self: @TContractState) -> u256;
        fn get_payment_limits(self: @TContractState) -> (u256, u256);
        fn get_success_rate(self: @TContractState) -> u256;
    }
}