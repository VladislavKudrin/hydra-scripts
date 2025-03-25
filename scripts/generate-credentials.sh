
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
    --add-peer)
      PEER="$2"
      shift 2
      ;;
    --generate-wallet)
      GENERATE_WALLET=1
      shift 1
      ;;
    --testnet-magic)
      NETWORK="$2"
      NETWORK_FLAG="--testnet-magic $NETWORK"
      shift 2
      ;;
    --mainnet)
      NETWORK_FLAG="--mainnet"
      shift 1
      ;;
    --help)
      echo "Usage: $0 --node-id <node id> [--testnet-magic <magic>] [--add-peer <host>:<node-port>:<api-host>:<api-port>] [--generate-wallet]"
      exit 0
      ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
  esac
done

# Keys generation

CREDENTIALS_DIR_NODE="${CREDENTIALS_DIR}/${NODE_ID}"
mkdir -p "$CREDENTIALS_DIR_NODE"
CARDANO_SIGNING_KEY="${CREDENTIALS_DIR_NODE}/${NODE_ID}-node.sk"  # Key for signing hydra node txs on layer 1 (fees, open/close heads, commit/decommit)
HYDRA_SIGNING_KEY="${CREDENTIALS_DIR_NODE}/${NODE_ID}-hydra.sk" # Key for signing txs on layer 2 (hydra layer) for this node / head 

if [ ! -f "$CARDANO_SIGNING_KEY" ]; then
  echo "Cardano signing key missing in ${CREDENTIALS_DIR_NODE}. Generating Cardano signing key..."
  cardano-cli address key-gen \
    --verification-key-file ${CREDENTIALS_DIR_NODE}/${NODE_ID}-node.vk \
    --signing-key-file ${CARDANO_SIGNING_KEY}
  
  cardano-cli address build \
  --verification-key-file  ${CREDENTIALS_DIR_NODE}/${NODE_ID}-node.vk \
  --out-file  ${CREDENTIALS_DIR_NODE}/${NODE_ID}-node.addr \
  $NETWORK_FLAG
else
  echo "Cardano signing key exists in ${CREDENTIALS_DIR_NODE}."
fi

if [ "$GENERATE_WALLET" -eq 1 ]; then
  echo "Wallet signing key missing in ${CREDENTIALS_DIR_NODE}. Generating Wallet signing key..."
  cardano-cli address key-gen \
    --verification-key-file ${CREDENTIALS_DIR_NODE}/${NODE_ID}-wallet.vk \
    --signing-key-file ${CREDENTIALS_DIR_NODE}/${NODE_ID}-wallet.sk
  
  cardano-cli address build \
  --verification-key-file  ${CREDENTIALS_DIR_NODE}/${NODE_ID}-wallet.vk \
  --out-file  ${CREDENTIALS_DIR_NODE}/${NODE_ID}-wallet.addr \
  $NETWORK_FLAG
else
  echo "Wallet signing key exists in ${CREDENTIALS_DIR_NODE}."
fi

if [ ! -f "$HYDRA_SIGNING_KEY" ]; then
  echo "Hydra signing key missing in ${CREDENTIALS_DIR_NODE}. Generating Hydra signing key..."
  hydra-node gen-hydra-key --output-file ${CREDENTIALS_DIR_NODE}/${NODE_ID}-hydra
else
  echo "Hydra signing key exists in ${CREDENTIALS_DIR_NODE}."
fi

if [ -n "$PEER" ]; then
  IFS=':' read -r peer_host node_port api_host api_port <<< "$PEER"
  echo "Adding peer for node-id ${NODE_ID}: host ${peer_host}, node port ${node_port}, api host ${api_host}, api port ${api_port}"
  
  peer_object=$(jq -n \
      --arg id "$NODE_ID" \
      --arg host "$peer_host" \
      --arg port "$node_port" \
      --arg api_host "$api_host" \
      --arg api_port "$api_port" \
      --arg vkey_cardano "${CREDENTIALS_DIR_NODE}/${NODE_ID}-node.vk" \
      --arg vkey_hydra "${CREDENTIALS_DIR_NODE}/${NODE_ID}-hydra.vk" \
      '{ "node-id": $id, "node-host": $host, "node-port": $port, "api-host": $api_host, "api-port": $api_port, "vkey-cardano": $vkey_cardano, "vkey-hydra": $vkey_hydra }')
  
  mkdir -p "${DATA_DIR}"
  
  current_peers=$(jq -c 'if type=="array" then . else [] end' "${DATA_DIR}/peers.json" 2>/dev/null || echo "[]")
  
  if echo "$current_peers" | jq --exit-status --arg id "$NODE_ID" 'any(.[]; .["node-id"] == $id)' >/dev/null; then
      echo "Peer with node-id ${NODE_ID} already exists in ${DATA_DIR}/peers.json. Skipping addition."
  else
      updated_peers=$(echo "$current_peers" | jq --argjson new "$peer_object" '. + [$new]')
      echo "$updated_peers" > "${DATA_DIR}/peers.json"
      echo "Peer added successfully."
  fi
fi
