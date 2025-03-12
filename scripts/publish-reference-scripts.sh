#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/env" ]; then
  source "${SCRIPT_DIR}/env"
else
  echo "Env file not found in ${SCRIPT_DIR}"
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --node-id)
      NODE_ID="$2"
      shift 2
      ;;
    --testnet-magic)
      NETWORK="$2"
      NETWORK_FLAG="--testnet-magic $NETWORK"
      shift 2
      ;;
    --signing-key-file)
      CARDANO_SIGNING_KEY="$2"
      shift 2
      ;;
    --mainnet)
      NETWORK_FLAG="--mainnet"
      shift 1
      ;;
    --help)
      echo "Usage: $0 --node-id <node id> [--testnet-magic <magic>] [--signing-key-file <signing key path>]"
      exit 0
      ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
  esac
done

if [ ! -f "$CARDANO_SIGNING_KEY" ]; then
  CARDANO_SIGNING_KEY="${CREDENTIALS_DIR}/${NODE_ID}/${NODE_ID}-node.sk"
fi

scripts=$(exec "${HNODEBIN}" publish-scripts \
    $NETWORK_FLAG \
    --node-socket $CARDANO_NODE_SOCKET_PATH \
    --cardano-signing-key $CARDANO_SIGNING_KEY)

json_scripts=$(echo "$scripts" | jq -R 'split(",")')
echo "$json_scripts" > data/reference-scripts.json

echo "Reference scripts saved to data/reference-scripts.json:"

