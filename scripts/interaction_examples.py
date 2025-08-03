#!/usr/bin/env python3
"""
Homebase Contract Interaction Examples
Demonstrates how to interact with all deployed contracts
"""

import asyncio
import json
import os
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.account.account import Account
from starknet_py.net.models import StarknetChainId
from starknet_py.net.signer.stark_curve_signer import KeyPair
from starknet_py.contract import Contract

class HomebaseInteraction:
    def __init__(self):
        self.network = os.getenv('NETWORK', 'testnet')
        self.account_address = os.getenv('ACCOUNT_ADDRESS')
        self.private_key = os.getenv('PRIVATE_KEY')
        
        # Load deployment addresses
        with open('deployment_addresses.json', 'r') as f:
            self.addresses = json.load(f)
        
        # Setup client and account
        self.client = FullNodeClient(
            node_url='https://alpha4.starknet.io' if self.network == 'testnet' 
            else 'https://alpha-mainnet.starknet.io'
        )
        
        key_pair = KeyPair.from_private_key(int(self.private_key, 16))
        chain_id = StarknetChainId.TESTNET if self.network == 'testnet' else StarknetChainId.MAINNET
        
        self.account = Account(
            address=self.account_address,
            client=self.client,
            key_pair=key_pair,
            chain=chain_id
        )
    
    async def setup_contracts(self):
        """Load all contract instances"""
        self.token_contract = await Contract.from_address(
            self.addresses['contracts']['hancoin_token'], 
            self.client
        )
        
        self.loan_contract = await Contract.from_address(
            self.addresses['contracts']['loan_contract'], 
            self.client
        )
        
        self.escrow_contract = await Contract.from_address(
            self.addresses['contracts']['escrow_contract'], 
            self.client
        )
        
        self.swap_contract = await Contract.from_address(
            self.addresses['contracts']['swap_contract'], 
            self.client
        )
        
        self.credit_card_contract = await Contract.from_address(
            self.addresses['contracts']['credit_card_simulator'], 
            self.client
        )
        
        print("✅ All contracts loaded successfully")

    async def token_interactions(self):
        """Demonstrate token contract interactions"""
        print("\n🪙 === TOKEN CONTRACT INTERACTIONS ===")
        
        # Check token details
        name = await self.token_contract.functions["name"].call()
        symbol = await self.token_contract.functions["symbol"].call()
        total_supply = await self.token_contract.functions["total_supply"].call()
        formatted_supply = await self.token_contract.functions["total_supply_formatted"].call()
        
        print(f"Token: {name.name} ({symbol.symbol})")
        print(f"Total Supply: {formatted_supply.result:,} HNXZ")
        
        # Check owner balance
        owner_balance = await self.token_contract.functions["balance_of"].call(self.account_address)
        print(f"Owner Balance: {owner_balance.balance / 10**18:,.2f} HNXZ")
        
        # Check paymaster status
        paymaster_enabled = await self.token_contract.functions["is_paymaster_enabled"].call()
        gas_fee_rate = await self.token_contract.functions["get_gas_fee_rate"].call()
        
        print(f"Paymaster Enabled: {paymaster_enabled.result}")
        print(f"Gas Fee Rate: {gas_fee_rate.result} wei per gas unit")
        
        # Example: Transfer tokens to test address
        test_recipient = "0x1234567890123456789012345678901234567890123456789012345678901234"
        transfer_amount = 1000 * 10**18  # 1000 HNXZ
        
        print(f"\n💸 Transferring {transfer_amount / 10**18} HNXZ to test address...")
        
        transfer_call = await self.token_contract.functions["transfer"].invoke_v1(
            test_recipient,
            transfer_amount,
            max_fee=int(1e17)
        )
        
        await transfer_call.wait_for_acceptance()
        print("✅ Transfer completed")
        
        # Check recipient balance
        recipient_balance = await self.token_contract.functions["balance_of"].call(test_recipient)
        print(f"Recipient Balance: {recipient_balance.balance / 10**18} HNXZ")

    async def loan_interactions(self):
        """Demonstrate loan contract interactions"""
        print("\n🏦 === LOAN CONTRACT INTERACTIONS ===")
        
        # Get loan contract stats
        total_issued = await self.loan_contract.functions["get_total_loans_issued"].call()
        total_repaid = await self.loan_contract.functions["get_total_amount_repaid"].call()
        collateral_ratio = await self.loan_contract.functions["get_collateral_ratio"].call()
        
        print(f"Total Loans Issued: {total_issued.result / 10**18:,.2f} HNXZ")
        print(f"Total Amount Repaid: {total_repaid.result / 10**18:,.2f} HNXZ")
        print(f"Required Collateral Ratio: {collateral_ratio.result / 100}%")
        
        # Example: Request a loan
        loan_amount = 5000 * 10**18  # 5k HNXZ
        duration = 86400 * 90  # 90 days
        collateral_amount = 7500 * 10**18  # 7.5k HNXZ (150% collateral)
        
        print(f"\n📋 Requesting loan: {loan_amount / 10**18} HNXZ for {duration // 86400} days")
        print(f"Collateral: {collateral_amount / 10**18} HNXZ")
        
        loan_request = await self.loan_contract.functions["request_loan"].invoke_v1(
            loan_amount,
            duration,
            collateral_amount,
            max_fee=int(1e17)
        )
        
        await loan_request.wait_for_acceptance()
        print("✅ Loan requested successfully")
        
        # Get loan details (assuming loan ID 1)
        try:
            loan_details = await self.loan_contract.functions["get_loan"].call(1)
            print(f"\n📊 Loan Details (ID: 1):")
            print(f"Borrower: {hex(loan_details.borrower)}")
            print(f"Amount: {loan_details.loan_amount / 10**18} HNXZ")
            print(f"Collateral: {loan_details.collateral_amount / 10**18} HNXZ")
            print(f"Status: {loan_details.status}")
            
            # Calculate total due
            total_due = await self.loan_contract.functions["calculate_total_due"].call(1)
            print(f"Total Due: {total_due.result / 10**18} HNXZ")
            
        except Exception as e:
            print(f"No existing loans found: {e}")

    async def escrow_interactions(self):
        """Demonstrate escrow contract interactions"""
        print("\n🔒 === ESCROW CONTRACT INTERACTIONS ===")
        
        # Get escrow stats
        total_escrowed = await self.escrow_contract.functions["get_total_escrowed"].call()
        total_fees = await self.escrow_contract.functions["get_total_fees_collected"].call()
        fee_rate = await self.escrow_contract.functions["get_escrow_fee_rate"].call()
        
        print(f"Total Escrowed: {total_escrowed.result / 10**18:,.2f} HNXZ")
        print(f"Total Fees Collected: {total_fees.result / 10**18:,.2f} HNXZ")
        print(f"Escrow Fee Rate: {fee_rate.result / 100}%")
        
        # Example: Create escrow order
        seller_address = "0x5678901234567890123456789012345678901234567890123456789012345678"
        escrow_amount = 25000 * 10**18  # 25k HNXZ
        property_id = int.from_bytes(b'PROP001', 'big')  # Convert string to felt252
        timeout_duration = 86400 * 30  # 30 days
        
        print(f"\n🏠 Creating escrow order:")
        print(f"Seller: {seller_address}")
        print(f"Amount: {escrow_amount / 10**18} HNXZ")
        print(f"Property ID: PROP001")
        print(f"Timeout: {timeout_duration // 86400} days")
        
        escrow_creation = await self.escrow_contract.functions["create_escrow"].invoke_v1(
            seller_address,
            escrow_amount,
            property_id,
            timeout_duration,
            max_fee=int(1e17)
        )
        
        await escrow_creation.wait_for_acceptance()
        print("✅ Escrow order created successfully")
        
        # Check escrow status (assuming order ID 1)
        try:
            escrow_status = await self.escrow_contract.functions["get_escrow_status"].call(1)
            escrow_order = await self.escrow_contract.functions["get_escrow_order"].call(1)
            
            print(f"\n📊 Escrow Order Details (ID: 1):")
            print(f"Buyer: {hex(escrow_order.buyer)}")
            print(f"Seller: {hex(escrow_order.seller)}")
            print(f"Amount: {escrow_order.amount / 10**18} HNXZ")
            print(f"Status: {escrow_status}")
            
        except Exception as e:
            print(f"No existing escrow orders found: {e}")

    async def swap_interactions(self):
        """Demonstrate swap contract interactions"""
        print("\n🔄 === SWAP CONTRACT INTERACTIONS ===")
        
        # Get swap stats
        total_swaps = await self.swap_contract.functions["get_total_swaps"].call()
        total_volume = await self.swap_contract.functions["get_total_volume"].call()
        swap_fee = await self.swap_contract.functions["get_swap_fee"].call()
        
        print(f"Total Swaps: {total_swaps.result}")
        print(f"Total Volume: {total_volume.result / 10**18:,.2f} HNXZ")
        print(f"Swap Fee: {swap_fee.result / 100}%")
        
        # Get supported tokens
        usdt_address = await self.swap_contract.functions["get_supported_token"].call('USDT')
        usdc_address = await self.swap_contract.functions["get_supported_token"].call('USDC')
        weth_address = await self.swap_contract.functions["get_supported_token"].call('WETH')
        
        print(f"\n💱 Supported Tokens:")
        print(f"USDT: {hex(usdt_address.result)}")
        print(f"USDC: {hex(usdc_address.result)}")
        print(f"WETH: {hex(weth_address.result)}")
        
        # Example: Get swap quote
        token_address = self.addresses['contracts']['hancoin_token']
        swap_amount = 1000 * 10**18  # 1000 HNXZ
        
        if usdt_address.result != 0:
            print(f"\n💰 Getting quote for {swap_amount / 10**18} HNXZ → USDT")
            
            try:
                quote = await self.swap_contract.functions["get_swap_quote"].call(
                    token_address,
                    usdt_address.result,
                    swap_amount
                )
                print(f"Quote: {quote.result / 10**18} USDT")
                
                # Example swap execution (commented out to avoid actual transaction)
                # print(f"Executing swap...")
                # swap_tx = await self.swap_contract.functions["swap_hnxz_to_usdt"].invoke_v1(
                #     swap_amount,
                #     int(quote.result * 0.95),  # 5% slippage tolerance
                #     max_fee=int(1e17)
                # )
                # await swap_tx.wait_for_acceptance()
                # print("✅ Swap completed")
                
            except Exception as e:
                print(f"Swap quote failed: {e}")
        else:
            print("USDT not configured for swaps")

    async def credit_card_interactions(self):
        """Demonstrate credit card simulator interactions"""
        print("\n💳 === CREDIT CARD SIMULATOR INTERACTIONS ===")
        
        # Get credit card stats
        total_payments = await self.credit_card_contract.functions["get_total_payments"].call()
        total_fiat = await self.credit_card_contract.functions["get_total_fiat_processed"].call()
        total_hnxz = await self.credit_card_contract.functions["get_total_hnxz_issued"].call()
        processing_fee = await self.credit_card_contract.functions["get_processing_fee_rate"].call()
        
        print(f"Total Payments: {total_payments.result}")
        print(f"Total Fiat Processed: ${total_fiat.result / 100:,.2f}")
        print(f"Total HNXZ Issued: {total_hnxz.result / 10**18:,.2f}")
        print(f"Processing Fee: {processing_fee.result / 100}%")
        
        # Get exchange rates
        usd_rate = await self.credit_card_contract.functions["get_exchange_rate"].call('USD')
        eur_rate = await self.credit_card_contract.functions["get_exchange_rate"].call('EUR')
        
        print(f"\n💱 Exchange Rates:")
        print(f"USD: ${usd_rate.rate / 100} per HNXZ")
        print(f"EUR: €{eur_rate.rate / 100} per HNXZ")
        
        # Example: Calculate HNXZ amount for $100
        fiat_amount = 10000  # $100.00 in cents
        currency = 'USD'
        
        hnxz_amount = await self.credit_card_contract.functions["calculate_hnxz_amount"].call(
            fiat_amount,
            currency
        )
        
        print(f"\n🧮 ${fiat_amount / 100} USD = {hnxz_amount.result / 10**18:,.2f} HNXZ")
        
        # Example: Initiate payment
        card_last_four = 1234
        
        print(f"💳 Initiating payment: ${fiat_amount / 100} USD")
        
        payment_initiation = await self.credit_card_contract.functions["initiate_payment"].invoke_v1(
            fiat_amount,
            currency,
            card_last_four,
            max_fee=int(1e17)
        )
        
        await payment_initiation.wait_for_acceptance()
        print("✅ Payment initiated successfully")
        
        # Check payment status (assuming payment ID 1)
        try:
            payment_status = await self.credit_card_contract.functions["get_payment_status"].call(1)
            payment_details = await self.credit_card_contract.functions["get_payment"].call(1)
            
            print(f"\n📊 Payment Details (ID: 1):")
            print(f"User: {hex(payment_details.user)}")
            print(f"Fiat Amount: ${payment_details.fiat_amount / 100}")
            print(f"HNXZ Amount: {payment_details.hnxz_amount / 10**18}")
            print(f"Status: {payment_status}")
            
        except Exception as e:
            print(f"No existing payments found: {e}")

    async def run_all_examples(self):
        """Run all interaction examples"""
        print("🚀 Starting Homebase Contract Interactions")
        print("=" * 50)
        
        await self.setup_contracts()
        
        try:
            await self.token_interactions()
            await self.loan_interactions()
            await self.escrow_interactions()
            await self.swap_interactions()
            await self.credit_card_interactions()
            
            print("\n" + "=" * 50)
            print("✅ All interactions completed successfully!")
            
        except Exception as e:
            print(f"❌ Error during interactions: {e}")
            raise

async def main():
    """Main function to run examples"""
    
    # Check if deployment addresses exist
    if not os.path.exists('deployment_addresses.json'):
        print("❌ deployment_addresses.json not found!")
        print("Please deploy contracts first using: ./scripts/deploy_all.sh")
        return
    
    # Check environment variables
    if not os.getenv('ACCOUNT_ADDRESS') or not os.getenv('PRIVATE_KEY'):
        print("❌ ACCOUNT_ADDRESS and PRIVATE_KEY must be set in .env file")
        return
    
    homebase = HomebaseInteraction()
    await homebase.run_all_examples()

if __name__ == "__main__":
    asyncio.run(main())