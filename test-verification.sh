#!/bin/bash
# Verification testing script
# Deploys canisters and runs verification tests with real transactions

set -e

echo "=== Verification Test Script ==="
echo ""

# Check if dfx is running
if ! dfx ping > /dev/null 2>&1; then
  echo "Starting local replica..."
  dfx start --background --clean
  sleep 3
fi

echo "1. Deploying EVM RPC canister..."
dfx deps pull
dfx deps init evm_rpc --argument '(record {})'
dfx deps deploy evm_rpc

echo ""
echo "2. Configuring EVM RPC with Alchemy API key..."
EVM_RPC_CANISTER=$(dfx canister id evm_rpc)
# Replace YOUR_ALCHEMY_API_KEY with your actual Alchemy API key
dfx canister call evm_rpc updateApiKeys "(vec { record { 9 : nat64; opt \"YOUR_ALCHEMY_API_KEY\" } })"

echo ""
echo "3. Deploying VerificationTest canister..."
dfx deploy VerificationTest

echo ""
echo "4. Running Hoosat verification test..."
dfx canister call VerificationTest testHoosatVerification

echo ""
echo "5. Running EVM verification test..."
dfx canister call VerificationTest testEVMVerification "(principal \"$EVM_RPC_CANISTER\")"

echo ""
echo "=== Tests Complete ==="
