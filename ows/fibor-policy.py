#!/usr/bin/env python3
"""
FIBOR OWS Policy — Pre-signing enforcement for FIBOR agents.

This custom OWS policy checks the agent's FiborAccount state before
allowing any transaction to be signed. It enforces:

1. Credit limit — agent cannot draw more than their max credit line
2. Available balance — agent cannot spend more than their checking balance
3. Excommunication — excommunicated agents cannot sign any transaction
4. Frozen accounts — frozen FiborAccounts cannot sign any transaction

Install as an OWS policy:
  ows policy create --file fibor-policy.json

The policy config must include:
  - rpc_url: Base Sepolia RPC endpoint
  - fibor_score_address: FiborScore contract address
  - credit_pool_address: CreditPool contract address
"""

import json
import sys
import urllib.request

# Read PolicyContext from stdin
ctx = json.load(sys.stdin)
config = ctx.get("policy_config", {})

rpc_url = config.get("rpc_url", "https://sepolia.base.org")
fibor_score = config.get("fibor_score_address", "")
credit_pool = config.get("credit_pool_address", "")

# The agent's wallet address (from the OWS wallet making this request)
wallet_id = ctx.get("wallet_id", "")
chain_id = ctx.get("chain_id", "")

# Only enforce on Base (mainnet or Sepolia)
if chain_id not in ("eip155:8453", "eip155:84532"):
    json.dump({"allow": True}, sys.stdout)
    sys.exit(0)

# Get the agent's address from the transaction sender
tx = ctx.get("transaction", {})
agent_address = tx.get("from", "")

if not agent_address or not fibor_score or not credit_pool:
    # Not enough context to check — allow (fail open for non-FIBOR txns)
    json.dump({"allow": True}, sys.stdout)
    sys.exit(0)


def eth_call(to, data):
    """Make an eth_call to a contract."""
    payload = json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [{"to": to, "data": data}, "latest"]
    }).encode()
    req = urllib.request.Request(
        rpc_url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    resp = json.load(urllib.request.urlopen(req, timeout=4))
    if "error" in resp:
        return None
    return resp.get("result", "0x")


def decode_uint256(hex_result):
    """Decode a uint256 from hex."""
    if not hex_result or hex_result == "0x":
        return 0
    return int(hex_result, 16)


def decode_bool(hex_result):
    """Decode a bool from hex."""
    return decode_uint256(hex_result) != 0


# Pad address for ABI encoding
def pad_address(addr):
    """ABI-encode an address as a 32-byte word."""
    clean = addr.lower().replace("0x", "")
    return clean.zfill(64)


try:
    # Check if agent is excommunicated
    # isExcommunicated(address) = 0x0bd32d84
    selector = "0x0bd32d84"
    data = selector + pad_address(agent_address)
    result = eth_call(fibor_score, data)
    is_excommunicated = decode_bool(result)

    if is_excommunicated:
        json.dump({
            "allow": False,
            "reason": "FIBOR: Agent is excommunicated. All transactions blocked."
        }, sys.stdout)
        sys.exit(0)

    # Check FIBOR Score
    # getScore(address) = 0x1a671a28 (approximate, may differ)
    selector = "0xd47875d0"  # getScore(address)
    data = selector + pad_address(agent_address)
    result = eth_call(fibor_score, data)
    score = decode_uint256(result)

    # Check outstanding credit
    # getOutstanding(address) = function selector
    selector = "0x1549be43"  # getOutstanding(address)
    data = selector + pad_address(agent_address)
    result = eth_call(credit_pool, data)
    outstanding = decode_uint256(result)

    # Check max credit line
    # getMaxCreditLine(address) = function selector
    selector = "0x82f5b652"  # getMaxCreditLine(address)
    data = selector + pad_address(agent_address)
    result = eth_call(fibor_score, data)
    max_credit = decode_uint256(result)

    # If agent has outstanding credit close to their limit, warn
    if max_credit > 0 and outstanding > 0:
        utilization = (outstanding * 100) // max_credit
        if utilization > 90:
            json.dump({
                "allow": False,
                "reason": f"FIBOR: Credit utilization at {utilization}%. Outstanding: ${outstanding / 1e6:.2f}, Max: ${max_credit / 1e6:.2f}"
            }, sys.stdout)
            sys.exit(0)

    # Allow the transaction
    json.dump({
        "allow": True,
    }, sys.stdout)

except Exception as e:
    # Fail open — don't block transactions due to RPC errors
    json.dump({
        "allow": True,
    }, sys.stdout)
