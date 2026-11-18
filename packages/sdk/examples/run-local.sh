#!/usr/bin/env bash
#
# Runs the stream example against a local stellar/quickstart node, so it does
# not depend on public testnet being up or unrate-limited.
#
#   docker compose -f examples/docker-compose.yml up -d
#   WASM_DIR=/path/to/sororail-contracts/target/wasm32v1-none/release \
#     bash examples/run-local.sh
#
# The local network is standalone: its passphrase is fixed and friendbot is on
# the quickstart container. Nothing here touches testnet or needs secrets.
set -euo pipefail

: "${WASM_DIR:?Set WASM_DIR to the directory holding the built contract .wasm files}"

RPC_URL="${RPC_URL:-http://localhost:8000/soroban/rpc}"
NETWORK_PASSPHRASE="Standalone Network ; February 2017"
export RPC_URL NETWORK_PASSPHRASE STELLAR_NETWORK=local

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> waiting for the local RPC at $RPC_URL"
for _ in $(seq 1 60); do
  if curl -sf -X POST -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' "$RPC_URL" | grep -q healthy; then
    break
  fi
  sleep 2
done
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' "$RPC_URL" | grep -q healthy \
  || { echo "Local RPC is not healthy. Is the quickstart container running?" >&2; exit 1; }

run_id="local$$"
payer="${run_id}_payer"
other="${run_id}_other"

echo "==> creating and funding accounts with friendbot"
stellar keys generate "$payer" --network local --fund
stellar keys generate "$other" --network local --fund

export SOROBAN_SECRET_KEY
SOROBAN_SECRET_KEY="$(stellar keys show "$payer")"
export RECIPIENT_PUBLIC_KEY
RECIPIENT_PUBLIC_KEY="$(stellar keys address "$other")"

echo "==> native token contract"
export TOKEN_ID
TOKEN_ID="$(stellar contract id asset --asset native --network local)"

echo "==> deploying a fresh stream contract"
wasm="$(find "$WASM_DIR" -maxdepth 1 -name '*stream*.wasm' | sort | head -n 1)"
[ -n "$wasm" ] || { echo "No stream .wasm in $WASM_DIR" >&2; exit 1; }
export STREAM_CONTRACT_ID
STREAM_CONTRACT_ID="$(stellar contract deploy --wasm "$wasm" --source "$payer" --network local)"

echo "==> running stream-lifecycle.ts"
pnpm exec tsx examples/stream-lifecycle.ts
