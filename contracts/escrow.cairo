// SPDX-License-Identifier: MIT
// Escrow Contract - Homebase Real Estate Transaction Escrow Service

#[starknet::contract]
mod EscrowContract {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[derive(Drop, Serde, starknet::Store)]
    struct EscrowOrder {
        id: u256,
        buyer: ContractAddress,
        seller: ContractAddress,
        amount: u256,
        property_id: felt252, // Identifier for the real estate property
        status: EscrowStatus,
        created_at: u64,
        timeout: u64,
        admin_approved: bool,
        buyer_confirmed: bool,
        seller_confirmed: bool,
        dispute_raised: bool,
        dispute_by: ContractAddress,
        resolution_deadline: u64,
    }

    #[derive(Drop, Serde, starknet::Store)]
    enum EscrowStatus {
        Created,        // Escrow created, waiting for funds
        Funded,         // Buyer has deposited funds
        InProgress,     // Both parties engaged, transaction in progress
        Completed,      // Successfully completed, funds released to seller
        Cancelled,      // Cancelled before completion
        Disputed,       // Dispute raised, awaiting resolution
        Resolved,       // Dispute resolved
        Expired,        // Timeout reached without completion
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        hancoin_token: ContractAddress,
        next_order_id: u256,
        escrow_orders: LegacyMap::<u256, EscrowOrder>,
        user_orders: LegacyMap::<ContractAddress, Array<u256>>, // User to order IDs
        escrow_fee_rate: u256, // Fee rate in basis points (e.g., 250 = 2.5%)
        min_escrow_amount: u256,
        max_escrow_amount: u256,
        default_timeout: u64, // Default timeout in seconds
        admin_wallet: ContractAddress, // Admin wallet for fee collection
        total_escrowed: u256,
        total_fees_collected: u256,
        dispute_resolution_time: u64, // Time allowed for dispute resolution
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        EscrowCreated: EscrowCreated,
        EscrowFunded: EscrowFunded,
        EscrowReleased: EscrowReleased,
        EscrowCancelled: EscrowCancelled,
        DisputeRaised: DisputeRaised,
        DisputeResolved: DisputeResolved,
        EscrowExpired: EscrowExpired,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowCreated {
        order_id: u256,
        buyer: ContractAddress,
        seller: ContractAddress,
        amount: u256,
        property_id: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowFunded {
        order_id: u256,
        buyer: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowReleased {
        order_id: u256,
        seller: ContractAddress,
        amount: u256,
        fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowCancelled {
        order_id: u256,
        cancelled_by: ContractAddress,
        refund_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DisputeRaised {
        order_id: u256,
        raised_by: ContractAddress,
        deadline: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct DisputeResolved {
        order_id: u256,
        resolved_by: ContractAddress,
        buyer_gets: u256,
        seller_gets: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowExpired {
        order_id: u256,
        refund_amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        hancoin_token: ContractAddress,
        admin_wallet: ContractAddress,
        escrow_fee_rate: u256, // e.g., 250 = 2.5%
    ) {
        self.ownable.initializer(owner);
        self.hancoin_token.write(hancoin_token);
        self.admin_wallet.write(admin_wallet);
        self.next_order_id.write(1);
        self.escrow_fee_rate.write(escrow_fee_rate);
        self.min_escrow_amount.write(1000 * 1000000000000000000); // 1000 HNXZ minimum
        self.max_escrow_amount.write(10000000 * 1000000000000000000); // 10M HNXZ maximum
        self.default_timeout.write(86400 * 30); // 30 days default
        self.dispute_resolution_time.write(86400 * 7); // 7 days for dispute resolution
        self.total_escrowed.write(0);
        self.total_fees_collected.write(0);
    }

    #[abi(embed_v0)]
    impl EscrowContractImpl of super::IEscrowContract<ContractState> {
        // Create new escrow order
        fn create_escrow(
            ref self: ContractState,
            seller: ContractAddress,
            amount: u256,
            property_id: felt252,
            timeout_duration: u64
        ) -> u256 {
            let buyer = get_caller_address();
            let order_id = self.next_order_id.read();
            
            // Validate parameters
            assert(seller != buyer, 'Buyer cannot be seller');
            assert(amount >= self.min_escrow_amount.read(), 'Amount below minimum');
            assert(amount <= self.max_escrow_amount.read(), 'Amount above maximum');
            
            let timeout = if timeout_duration > 0 {
                timeout_duration
            } else {
                self.default_timeout.read()
            };
            
            // Create escrow order
            let current_time = get_block_timestamp();
            let escrow_order = EscrowOrder {
                id: order_id,
                buyer,
                seller,
                amount,
                property_id,
                status: EscrowStatus::Created,
                created_at: current_time,
                timeout: current_time + timeout,
                admin_approved: false,
                buyer_confirmed: false,
                seller_confirmed: false,
                dispute_raised: false,
                dispute_by: starknet::contract_address_const::<0>(),
                resolution_deadline: 0,
            };
            
            // Store order
            self.escrow_orders.write(order_id, escrow_order);
            self.next_order_id.write(order_id + 1);
            
            self.emit(EscrowCreated { order_id, buyer, seller, amount, property_id });
            
            order_id
        }

        // Fund escrow (buyer deposits HNXZ)
        fn fund_escrow(ref self: ContractState, order_id: u256) {
            let mut order = self.escrow_orders.read(order_id);
            let caller = get_caller_address();
            
            assert(order.buyer == caller, 'Only buyer can fund');
            assert(order.status == EscrowStatus::Created, 'Order not in created state');
            assert(get_block_timestamp() <= order.timeout, 'Order expired');
            
            // Transfer HNXZ from buyer to this contract
            self._transfer_from_user(caller, order.amount);
            
            // Update order status
            order.status = EscrowStatus::Funded;
            self.escrow_orders.write(order_id, order);
            
            // Update total escrowed
            let current_total = self.total_escrowed.read();
            self.total_escrowed.write(current_total + order.amount);
            
            self.emit(EscrowFunded { order_id, buyer: caller, amount: order.amount });
        }

        // Confirm transaction (both parties must confirm)
        fn confirm_transaction(ref self: ContractState, order_id: u256) {
            let mut order = self.escrow_orders.read(order_id);
            let caller = get_caller_address();
            
            assert(order.status == EscrowStatus::Funded, 'Order not funded');
            assert(caller == order.buyer || caller == order.seller, 'Not authorized');
            assert(get_block_timestamp() <= order.timeout, 'Order expired');
            assert(!order.dispute_raised, 'Dispute is active');
            
            // Update confirmations
            if caller == order.buyer {
                order.buyer_confirmed = true;
            } else {
                order.seller_confirmed = true;
            }
            
            // If both confirmed, update status
            if order.buyer_confirmed && order.seller_confirmed {
                order.status = EscrowStatus::InProgress;
            }
            
            self.escrow_orders.write(order_id, order);
        }

        // Release funds to seller (admin or automatic after both confirmations)
        fn release_escrow(ref self: ContractState, order_id: u256) {
            let mut order = self.escrow_orders.read(order_id);
            let caller = get_caller_address();
            
            // Check authorization
            let is_admin = caller == self.ownable.owner();
            let auto_release = order.buyer_confirmed && order.seller_confirmed && 
                              order.status == EscrowStatus::InProgress;
            
            assert(is_admin || auto_release, 'Not authorized to release');
            assert(!order.dispute_raised, 'Cannot release during dispute');
            assert(order.status == EscrowStatus::Funded || order.status == EscrowStatus::InProgress, 'Invalid status');
            
            // Calculate fee and net amount
            let fee = (order.amount * self.escrow_fee_rate.read()) / 10000;
            let net_amount = order.amount - fee;
            
            // Transfer funds
            self._transfer_to_user(order.seller, net_amount);
            if fee > 0 {
                self._transfer_to_user(self.admin_wallet.read(), fee);
            }
            
            // Update order status
            order.status = EscrowStatus::Completed;
            self.escrow_orders.write(order_id, order);
            
            // Update statistics
            let current_total = self.total_escrowed.read();
            self.total_escrowed.write(current_total - order.amount);
            let current_fees = self.total_fees_collected.read();
            self.total_fees_collected.write(current_fees + fee);
            
            self.emit(EscrowReleased { order_id, seller: order.seller, amount: net_amount, fee });
        }

        // Raise dispute
        fn raise_dispute(ref self: ContractState, order_id: u256) {
            let mut order = self.escrow_orders.read(order_id);
            let caller = get_caller_address();
            
            assert(caller == order.buyer || caller == order.seller, 'Not authorized');
            assert(order.status == EscrowStatus::Funded || order.status == EscrowStatus::InProgress, 'Invalid status');
            assert(!order.dispute_raised, 'Dispute already raised');
            assert(get_block_timestamp() <= order.timeout, 'Order expired');
            
            // Raise dispute
            order.dispute_raised = true;
            order.dispute_by = caller;
            order.status = EscrowStatus::Disputed;
            order.resolution_deadline = get_block_timestamp() + self.dispute_resolution_time.read();
            
            self.escrow_orders.write(order_id, order);
            
            self.emit(DisputeRaised { 
                order_id, 
                raised_by: caller, 
                deadline: order.resolution_deadline 
            });
        }

        // Resolve dispute (admin only)
        fn resolve_dispute(
            ref self: ContractState, 
            order_id: u256, 
            buyer_percentage: u256 // 0-10000 (0% to 100%)
        ) {
            self.ownable.assert_only_owner();
            let mut order = self.escrow_orders.read(order_id);
            
            assert(order.status == EscrowStatus::Disputed, 'No active dispute');
            assert(buyer_percentage <= 10000, 'Invalid percentage');
            
            // Calculate amounts
            let fee = (order.amount * self.escrow_fee_rate.read()) / 10000;
            let net_amount = order.amount - fee;
            
            let buyer_gets = (net_amount * buyer_percentage) / 10000;
            let seller_gets = net_amount - buyer_gets;
            
            // Transfer funds
            if buyer_gets > 0 {
                self._transfer_to_user(order.buyer, buyer_gets);
            }
            if seller_gets > 0 {
                self._transfer_to_user(order.seller, seller_gets);
            }
            if fee > 0 {
                self._transfer_to_user(self.admin_wallet.read(), fee);
            }
            
            // Update order
            order.status = EscrowStatus::Resolved;
            self.escrow_orders.write(order_id, order);
            
            // Update statistics
            let current_total = self.total_escrowed.read();
            self.total_escrowed.write(current_total - order.amount);
            let current_fees = self.total_fees_collected.read();
            self.total_fees_collected.write(current_fees + fee);
            
            self.emit(DisputeResolved { 
                order_id, 
                resolved_by: get_caller_address(), 
                buyer_gets, 
                seller_gets 
            });
        }

        // Cancel escrow (before funding or by admin)
        fn cancel_escrow(ref self: ContractState, order_id: u256) {
            let mut order = self.escrow_orders.read(order_id);
            let caller = get_caller_address();
            
            let can_cancel = (order.status == EscrowStatus::Created && caller == order.buyer) || 
                           caller == self.ownable.owner();
            
            assert(can_cancel, 'Cannot cancel escrow');
            
            let refund_amount = if order.status == EscrowStatus::Funded {
                order.amount
            } else {
                0
            };
            
            // Refund if necessary
            if refund_amount > 0 {
                self._transfer_to_user(order.buyer, refund_amount);
                let current_total = self.total_escrowed.read();
                self.total_escrowed.write(current_total - refund_amount);
            }
            
            // Update order
            order.status = EscrowStatus::Cancelled;
            self.escrow_orders.write(order_id, order);
            
            self.emit(EscrowCancelled { order_id, cancelled_by: caller, refund_amount });
        }

        // Handle expired escrows
        fn handle_expired_escrow(ref self: ContractState, order_id: u256) {
            let mut order = self.escrow_orders.read(order_id);
            
            assert(get_block_timestamp() > order.timeout, 'Order not expired');
            assert(order.status == EscrowStatus::Funded || order.status == EscrowStatus::InProgress, 'Invalid status');
            
            // Refund to buyer
            self._transfer_to_user(order.buyer, order.amount);
            
            // Update order
            order.status = EscrowStatus::Expired;
            self.escrow_orders.write(order_id, order);
            
            // Update statistics
            let current_total = self.total_escrowed.read();
            self.total_escrowed.write(current_total - order.amount);
            
            self.emit(EscrowExpired { order_id, refund_amount: order.amount });
        }

        // Get escrow order details
        fn get_escrow_order(self: @ContractState, order_id: u256) -> EscrowOrder {
            self.escrow_orders.read(order_id)
        }

        // Get escrow status
        fn get_escrow_status(self: @ContractState, order_id: u256) -> EscrowStatus {
            let order = self.escrow_orders.read(order_id);
            order.status
        }

        // Get statistics
        fn get_total_escrowed(self: @ContractState) -> u256 {
            self.total_escrowed.read()
        }

        fn get_total_fees_collected(self: @ContractState) -> u256 {
            self.total_fees_collected.read()
        }

        fn get_escrow_fee_rate(self: @ContractState) -> u256 {
            self.escrow_fee_rate.read()
        }

        // Admin functions
        fn set_escrow_fee_rate(ref self: ContractState, new_rate: u256) {
            self.ownable.assert_only_owner();
            assert(new_rate <= 1000, 'Fee rate too high'); // Max 10%
            self.escrow_fee_rate.write(new_rate);
        }

        fn set_admin_wallet(ref self: ContractState, new_admin: ContractAddress) {
            self.ownable.assert_only_owner();
            self.admin_wallet.write(new_admin);
        }

        fn set_min_escrow_amount(ref self: ContractState, new_amount: u256) {
            self.ownable.assert_only_owner();
            self.min_escrow_amount.write(new_amount);
        }

        fn set_max_escrow_amount(ref self: ContractState, new_amount: u256) {
            self.ownable.assert_only_owner();
            self.max_escrow_amount.write(new_amount);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _transfer_from_user(ref self: ContractState, from: ContractAddress, amount: u256) {
            // Transfer tokens from user to this contract
            // In production, implement actual HNXZ token transfer
        }

        fn _transfer_to_user(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Transfer tokens from this contract to user
            // In production, implement actual HNXZ token transfer
        }
    }

    #[starknet::interface]
    trait IEscrowContract<TContractState> {
        fn create_escrow(
            ref self: TContractState,
            seller: ContractAddress,
            amount: u256,
            property_id: felt252,
            timeout_duration: u64
        ) -> u256;
        fn fund_escrow(ref self: TContractState, order_id: u256);
        fn confirm_transaction(ref self: TContractState, order_id: u256);
        fn release_escrow(ref self: TContractState, order_id: u256);
        fn raise_dispute(ref self: TContractState, order_id: u256);
        fn resolve_dispute(ref self: TContractState, order_id: u256, buyer_percentage: u256);
        fn cancel_escrow(ref self: TContractState, order_id: u256);
        fn handle_expired_escrow(ref self: TContractState, order_id: u256);
        fn get_escrow_order(self: @TContractState, order_id: u256) -> EscrowOrder;
        fn get_escrow_status(self: @TContractState, order_id: u256) -> EscrowStatus;
        fn get_total_escrowed(self: @TContractState) -> u256;
        fn get_total_fees_collected(self: @TContractState) -> u256;
        fn get_escrow_fee_rate(self: @TContractState) -> u256;
        fn set_escrow_fee_rate(ref self: TContractState, new_rate: u256);
        fn set_admin_wallet(ref self: TContractState, new_admin: ContractAddress);
        fn set_min_escrow_amount(ref self: TContractState, new_amount: u256);
        fn set_max_escrow_amount(ref self: TContractState, new_amount: u256);
    }
}