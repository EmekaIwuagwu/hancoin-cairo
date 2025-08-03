#!/usr/bin/env python3
"""
Homebase Token Deployment Script
Deploys the Hancoin (HNXZ) token contract to Starknet
"""

import asyncio
import os
import json
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.account.account import Account
from starknet_py.net.models import StarknetChainId
from starknet_py.net.signer.stark_curve_signer import KeyPair
from starknet_py.contract import Contract

# Configuration
NETWORK_URL = {
    'testnet': 'https://alpha4.starknet.io',
    'mainnet': 'https://alpha-mainnet.starknet.io'
}

async def deploy_token():
    """Deploy the Hancoin token contract"""
    
    # Load configuration from environment
    network = os.getenv('NETWORK', 'testnet')
    account_address = os.getenv('ACCOUNT_ADDRESS')
    private_key = os.getenv('PRIVATE_KEY')
    
    if not account_address or not private_key:
        raise ValueError("ACCOUNT_ADDRESS and PRIVATE_KEY must be set in environment")
    
    print(f"🚀 Deploying Hancoin Token to {network}...")
    print(f"Account: {account_address}")
    
    # Setup client and account
    client = FullNodeClient(node_url=NETWORK_URL[network])
    key_pair = KeyPair.from_private_key(int(private_key, 16))
    chain_id = StarknetChainId.TESTNET if network == 'testnet' else StarknetChainId.MAINNET
    
    account = Account(
        address=account_address,
        client=client,
        key_pair=key_pair,
        chain=chain_id
    )
    
    # Load compiled contract
    try:
        with open('target/dev/homebase_starknet_HancoinToken.contract_class.json', 'r') as f:
            contract_class = json.load(f)
    except FileNotFoundError:
        print("❌ Contract class file not found. Please run 'scarb build' first.")
        return
    
    # Deploy contract
    print("📦 Deploying contract...")
    
    deploy_result = await Contract.deploy_contract(
        account=account,
        class_hash=None,  # Will be computed from contract_class
        abi=contract_class['abi'],
        constructor_args=[account_address],  # Owner address
        cairo_version=1
    )
    
    # Wait for deployment
    print("⏳ Waiting for deployment confirmation...")
    await deploy_result.wait_for_acceptance()
    
    contract_address = deploy_result.deployed_contract.address
    print(f"✅ Hancoin Token deployed successfully!")
    print(f"Contract address: {hex(contract_address)}")
    
    # Verify deployment by checking token details
    print("\n🔍 Verifying deployment...")
    
    contract = deploy_result.deployed_contract
    
    # Get token information
    name = await contract.functions["name"].call()
    symbol = await contract.functions["symbol"].call()
    decimals = await contract.functions["decimals"].call()
    total_supply = await contract.functions["total_supply"].call()
    owner_balance = await contract.functions["balance_of"].call(account_address)
    
    print(f"Token Name: {name.name}")
    print(f"Token Symbol: {symbol.symbol}")
    print(f"Decimals: {decimals.decimals}")
    print(f"Total Supply: {total_supply.total_supply / 10**18:,.0f} HNXZ")
    print(f"Owner Balance: {owner_balance.balance / 10**18:,.0f} HNXZ")
    
    # Check paymaster functionality
    paymaster_enabled = await contract.functions["is_paymaster_enabled"].call()
    gas_fee_rate = await contract.functions["get_gas_fee_rate"].call()
    
    print(f"Paymaster Enabled: {paymaster_enabled.result}")
    print(f"Gas Fee Rate: {gas_fee_rate.result} wei per gas unit")
    
    # Save deployment info
    deployment_info = {
        'network': network,
        'contract_address': hex(contract_address),
        'deployer': account_address,
        'transaction_hash': hex(deploy_result.hash),
        'block_number': deploy_result.block_number,
        'token_info': {
            'name': name.name,
            'symbol': symbol.symbol,
            'decimals': decimals.decimals,
            'total_supply': str(total_supply.total_supply),
            'formatted_supply': f"{total_supply.total_supply / 10**18:,.0f}"
        }
    }
    
    with open('token_deployment.json', 'w') as f:
        json.dump(deployment_info, f, indent=2)
    
    print(f"\n💾 Deployment info saved to token_deployment.json")
    
    # Example interactions
    print("\n📋 Example interactions:")
    print(f"# Check balance:")
    print(f"starkli call {hex(contract_address)} balance_of <address>")
    print(f"\n# Transfer tokens:")
    print(f"starkli invoke {hex(contract_address)} transfer <to_address> <amount>")
    print(f"\n# Mint tokens (owner only):")
    print(f"starkli invoke {hex(contract_address)} mint <to_address> <amount>")
    print(f"\n# Set paymaster:")
    print(f"starkli invoke {hex(contract_address)} set_paymaster <paymaster_address> 1")
    
    return contract_address, contract

async def test_token_functions(contract_address: int, account: Account):
    """Test various token functions after deployment"""
    
    print("\n🧪 Testing token functions...")
    
    client = account.client
    contract = await Contract.from_address(contract_address, client)
    
    # Test minting (as owner)
    test_recipient = "0x1234567890123456789012345678901234567890123456789012345678901234"
    mint_amount = 1000 * 10**18  # 1000 HNXZ
    
    print(f"Minting {mint_amount / 10**18} HNXZ to test recipient...")
    
    mint_call = await contract.functions["mint"].invoke_v1(
        test_recipient,
        mint_amount,
        max_fee=int(1e17)
    )
    
    await mint_call.wait_for_acceptance()
    print("✅ Mint transaction confirmed")
    
    # Check recipient balance
    recipient_balance = await contract.functions["balance_of"].call(test_recipient)
    print(f"Test recipient balance: {recipient_balance.balance / 10**18} HNXZ")
    
    # Test gas fee rate adjustment
    new_gas_rate = 2000000000000000  # 0.002 HNXZ per gas unit
    
    print(f"Setting new gas fee rate: {new_gas_rate}")
    
    gas_rate_call = await contract.functions["set_gas_fee_rate"].invoke_v1(
        new_gas_rate,
        max_fee=int(1e17)
    )
    
    await gas_rate_call.wait_for_acceptance()
    print("✅ Gas fee rate updated")
    
    # Verify new rate
    updated_rate = await contract.functions["get_gas_fee_rate"].call()
    print(f"New gas fee rate: {updated_rate.result}")

if __name__ == "__main__":
    asyncio.run(deploy_token())