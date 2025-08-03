// SPDX-License-Identifier: MIT
// Loan Contract - Homebase Real Estate Loan Management with HNXZ Collateral

#[starknet::contract]
mod LoanContract {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[derive(Drop, Serde, starknet::Store)]
    struct Loan {
        id: u256,
        borrower: ContractAddress,
        loan_amount: u256,
        collateral_amount: u256,
        interest_rate: u256, // Basis points (e.g., 500 = 5%)
        duration: u64, // Duration in seconds
        start_time: u64,
        end_time: u64,
        status: LoanStatus,
        amount_repaid: u256,
        collateral_locked: bool,
    }

    #[derive(Drop, Serde, starknet::Store)]
    enum LoanStatus {
        Pending,
        Active,
        Repaid,
        Defaulted,
        Cancelled,
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        hancoin_token: ContractAddress,
        next_loan_id: u256,
        loans: LegacyMap::<u256, Loan>,
        user_loans: LegacyMap::<ContractAddress, Array<u256>>, // User to loan IDs
        collateral_ratio: u256, // Required collateral ratio (basis points)
        max_loan_amount: u256,
        min_loan_duration: u64,
        max_loan_duration: u64,
        default_interest_rate: u256,
        total_loans_issued: u256,
        total_amount_repaid: u256,
        protocol_fees: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        LoanRequested: LoanRequested,
        LoanApproved: LoanApproved,
        LoanDisbursed: LoanDisbursed,
        LoanRepayment: LoanRepayment,
        LoanDefaulted: LoanDefaulted,
        CollateralSeized: CollateralSeized,
    }

    #[derive(Drop, starknet::Event)]
    struct LoanRequested {
        loan_id: u256,
        borrower: ContractAddress,
        amount: u256,
        collateral: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LoanApproved {
        loan_id: u256,
        borrower: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct LoanDisbursed {
        loan_id: u256,
        borrower: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LoanRepayment {
        loan_id: u256,
        borrower: ContractAddress,
        amount: u256,
        remaining_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LoanDefaulted {
        loan_id: u256,
        borrower: ContractAddress,
        outstanding_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct CollateralSeized {
        loan_id: u256,
        borrower: ContractAddress,
        collateral_amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        hancoin_token: ContractAddress,
        collateral_ratio: u256, // e.g., 15000 = 150%
        default_interest_rate: u256, // e.g., 1000 = 10%
    ) {
        self.ownable.initializer(owner);
        self.hancoin_token.write(hancoin_token);
        self.next_loan_id.write(1);
        self.collateral_ratio.write(collateral_ratio);
        self.max_loan_amount.write(100000 * 1000000000000000000); // 100k HNXZ
        self.min_loan_duration.write(86400 * 30); // 30 days
        self.max_loan_duration.write(86400 * 365); // 1 year
        self.default_interest_rate.write(default_interest_rate);
        self.total_loans_issued.write(0);
        self.total_amount_repaid.write(0);
        self.protocol_fees.write(0);
    }

    #[abi(embed_v0)]
    impl LoanContractImpl of super::ILoanContract<ContractState> {
        // Request a loan with collateral
        fn request_loan(
            ref self: ContractState,
            loan_amount: u256,
            duration: u64,
            collateral_amount: u256
        ) -> u256 {
            let borrower = get_caller_address();
            let loan_id = self.next_loan_id.read();
            
            // Validate loan parameters
            assert(loan_amount > 0, 'Loan amount must be positive');
            assert(loan_amount <= self.max_loan_amount.read(), 'Loan amount too high');
            assert(duration >= self.min_loan_duration.read(), 'Duration too short');
            assert(duration <= self.max_loan_duration.read(), 'Duration too long');
            
            // Check collateral requirement
            let required_collateral = (loan_amount * self.collateral_ratio.read()) / 10000;
            assert(collateral_amount >= required_collateral, 'Insufficient collateral');
            
            // Create loan struct
            let current_time = get_block_timestamp();
            let loan = Loan {
                id: loan_id,
                borrower,
                loan_amount,
                collateral_amount,
                interest_rate: self.default_interest_rate.read(),
                duration,
                start_time: current_time,
                end_time: current_time + duration,
                status: LoanStatus::Pending,
                amount_repaid: 0,
                collateral_locked: false,
            };
            
            // Store loan
            self.loans.write(loan_id, loan);
            
            // Update user loans array (simplified - in production use proper array handling)
            // self.user_loans.write(borrower, updated_array);
            
            // Increment loan ID counter
            self.next_loan_id.write(loan_id + 1);
            
            self.emit(LoanRequested { 
                loan_id, 
                borrower, 
                amount: loan_amount, 
                collateral: collateral_amount 
            });
            
            loan_id
        }

        // Approve and disburse loan (owner only)
        fn approve_and_disburse_loan(ref self: ContractState, loan_id: u256) {
            self.ownable.assert_only_owner();
            let mut loan = self.loans.read(loan_id);
            
            assert(loan.status == LoanStatus::Pending, 'Loan not pending');
            
            // Lock collateral (transfer from borrower to contract)
            self._lock_collateral(loan.borrower, loan.collateral_amount);
            
            // Update loan status
            loan.status = LoanStatus::Active;
            loan.collateral_locked = true;
            loan.start_time = get_block_timestamp();
            loan.end_time = loan.start_time + loan.duration;
            self.loans.write(loan_id, loan);
            
            // Disburse loan amount to borrower
            self._transfer_tokens(loan.borrower, loan.loan_amount);
            
            // Update statistics
            let total_issued = self.total_loans_issued.read();
            self.total_loans_issued.write(total_issued + loan.loan_amount);
            
            self.emit(LoanApproved { loan_id, borrower: loan.borrower });
            self.emit(LoanDisbursed { 
                loan_id, 
                borrower: loan.borrower, 
                amount: loan.loan_amount 
            });
        }

        // Make loan repayment
        fn repay_loan(ref self: ContractState, loan_id: u256, amount: u256) {
            let mut loan = self.loans.read(loan_id);
            let caller = get_caller_address();
            
            assert(loan.borrower == caller, 'Not loan borrower');
            assert(loan.status == LoanStatus::Active, 'Loan not active');
            assert(amount > 0, 'Repayment amount must be positive');
            
            // Calculate total amount due (principal + interest)
            let total_due = self._calculate_total_due(loan_id);
            let remaining_balance = total_due - loan.amount_repaid;
            
            assert(amount <= remaining_balance, 'Repayment exceeds balance');
            
            // Transfer repayment from borrower to contract
            self._transfer_from_borrower(caller, amount);
            
            // Update loan
            loan.amount_repaid += amount;
            let new_remaining = remaining_balance - amount;
            
            if new_remaining == 0 {
                // Loan fully repaid
                loan.status = LoanStatus::Repaid;
                // Release collateral
                self._release_collateral(loan.borrower, loan.collateral_amount);
                loan.collateral_locked = false;
            }
            
            self.loans.write(loan_id, loan);
            
            // Update statistics
            let total_repaid = self.total_amount_repaid.read();
            self.total_amount_repaid.write(total_repaid + amount);
            
            self.emit(LoanRepayment { 
                loan_id, 
                borrower: caller, 
                amount, 
                remaining_balance: new_remaining 
            });
        }

        // Check for defaulted loans and handle them
        fn handle_default(ref self: ContractState, loan_id: u256) {
            let mut loan = self.loans.read(loan_id);
            let current_time = get_block_timestamp();
            
            assert(loan.status == LoanStatus::Active, 'Loan not active');
            assert(current_time > loan.end_time, 'Loan not overdue');
            
            // Calculate outstanding amount
            let total_due = self._calculate_total_due(loan_id);
            let outstanding = total_due - loan.amount_repaid;
            
            // Mark as defaulted
            loan.status = LoanStatus::Defaulted;
            self.loans.write(loan_id, loan);
            
            // Seize collateral
            if loan.collateral_locked {
                self._seize_collateral(loan.collateral_amount);
                loan.collateral_locked = false;
                self.loans.write(loan_id, loan);
                
                self.emit(CollateralSeized { 
                    loan_id, 
                    borrower: loan.borrower, 
                    collateral_amount: loan.collateral_amount 
                });
            }
            
            self.emit(LoanDefaulted { 
                loan_id, 
                borrower: loan.borrower, 
                outstanding_amount: outstanding 
            });
        }

        // Get loan details
        fn get_loan(self: @ContractState, loan_id: u256) -> Loan {
            self.loans.read(loan_id)
        }

        // Get loan history for a user
        fn get_user_loan_count(self: @ContractState, user: ContractAddress) -> u256 {
            // Simplified implementation - in production, maintain proper user loan arrays
            let mut count = 0;
            let total_loans = self.next_loan_id.read() - 1;
            let mut i = 1;
            
            loop {
                if i > total_loans {
                    break;
                }
                let loan = self.loans.read(i);
                if loan.borrower == user {
                    count += 1;
                }
                i += 1;
            };
            
            count
        }

        // Calculate total amount due (principal + interest)
        fn calculate_total_due(self: @ContractState, loan_id: u256) -> u256 {
            self._calculate_total_due(loan_id)
        }

        // Get contract statistics
        fn get_total_loans_issued(self: @ContractState) -> u256 {
            self.total_loans_issued.read()
        }

        fn get_total_amount_repaid(self: @ContractState) -> u256 {
            self.total_amount_repaid.read()
        }

        fn get_collateral_ratio(self: @ContractState) -> u256 {
            self.collateral_ratio.read()
        }

        // Admin functions
        fn set_collateral_ratio(ref self: ContractState, new_ratio: u256) {
            self.ownable.assert_only_owner();
            self.collateral_ratio.write(new_ratio);
        }

        fn set_interest_rate(ref self: ContractState, new_rate: u256) {
            self.ownable.assert_only_owner();
            self.default_interest_rate.write(new_rate);
        }

        fn set_max_loan_amount(ref self: ContractState, new_amount: u256) {
            self.ownable.assert_only_owner();
            self.max_loan_amount.write(new_amount);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _calculate_total_due(self: @ContractState, loan_id: u256) -> u256 {
            let loan = self.loans.read(loan_id);
            let principal = loan.loan_amount;
            let interest_rate = loan.interest_rate; // basis points
            let duration_years = loan.duration / (365 * 86400); // Convert seconds to years
            
            // Simple interest calculation: Principal * (1 + rate * time)
            let interest = (principal * interest_rate * duration_years) / 10000;
            principal + interest
        }

        fn _lock_collateral(ref self: ContractState, borrower: ContractAddress, amount: u256) {
            // Transfer collateral from borrower to this contract
            // In production, implement actual token transfer
        }

        fn _release_collateral(ref self: ContractState, borrower: ContractAddress, amount: u256) {
            // Transfer collateral back to borrower
            // In production, implement actual token transfer
        }

        fn _seize_collateral(ref self: ContractState, amount: u256) {
            // Keep collateral in contract (already locked)
            let current_fees = self.protocol_fees.read();
            self.protocol_fees.write(current_fees + amount);
        }

        fn _transfer_tokens(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Transfer loan amount to borrower
            // In production, implement actual token transfer from contract reserves
        }

        fn _transfer_from_borrower(ref self: ContractState, from: ContractAddress, amount: u256) {
            // Transfer repayment from borrower to contract
            // In production, implement actual token transfer
        }
    }

    #[starknet::interface]
    trait ILoanContract<TContractState> {
        fn request_loan(
            ref self: TContractState,
            loan_amount: u256,
            duration: u64,
            collateral_amount: u256
        ) -> u256;
        fn approve_and_disburse_loan(ref self: TContractState, loan_id: u256);
        fn repay_loan(ref self: TContractState, loan_id: u256, amount: u256);
        fn handle_default(ref self: TContractState, loan_id: u256);
        fn get_loan(self: @TContractState, loan_id: u256) -> Loan;
        fn get_user_loan_count(self: @TContractState, user: ContractAddress) -> u256;
        fn calculate_total_due(self: @TContractState, loan_id: u256) -> u256;
        fn get_total_loans_issued(self: @TContractState) -> u256;
        fn get_total_amount_repaid(self: @TContractState) -> u256;
        fn get_collateral_ratio(self: @TContractState) -> u256;
        fn set_collateral_ratio(ref self: TContractState, new_ratio: u256);
        fn set_interest_rate(ref self: TContractState, new_rate: u256);
        fn set_max_loan_amount(ref self: TContractState, new_amount: u256);
    }
}