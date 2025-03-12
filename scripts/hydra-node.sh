#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/env" ]; then
  source "${SCRIPT_DIR}/env"
else
  echo "Env file not found in ${SCRIPT_DIR}"
fi

stop_node() {
  HNODE_PID=$(pgrep -fn "$(basename ${HNODEBIN}).*.--port ${HNODE_PORT}" 2>/dev/null)
  kill -2 ${HNODE_PID} 2>/dev/null
  sleep 5
  exit 0
}

deploy_systemd() {
  echo "Deploying hydra-node-${NODE_ID} as systemd service.."
  sudo bash -c "cat <<-'EOF' > /etc/systemd/system/hydra-node-${NODE_ID}.service
	[Unit]
	Description=Hydra Node
	Wants=network-online.target
	After=network-online.target
	StartLimitIntervalSec=600
	StartLimitBurst=5
	
	[Service]
	Type=simple
	Restart=on-failure
	RestartSec=60
	User=${USER}
	LimitNOFILE=1048576
	WorkingDirectory=${SCRIPT_DIR}
	ExecStart=/bin/bash -l -c \"exec ${SCRIPT_DIR}/hydra-node.sh\"
	ExecStop=/bin/bash -l -c \"exec ${SCRIPT_DIR}/hydra-node.sh -s\"
	KillSignal=SIGINT
	SuccessExitStatus=143
	SyslogIdentifier=hydra-node-${NODE_ID}
	TimeoutStopSec=60
	
	[Install]
	WantedBy=multi-user.target
	EOF" && echo "hydra-node-${NODE_ID}.service deployed successfully!!" && sudo systemctl daemon-reload && sudo systemctl enable hydra-node-${NODE_ID}.service
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -d|--deploy-systemd)
      DEPLOY_SYSTEMD="Y"
      shift 1
      ;;
    -s|--stop-node)
      STOP_NODE="Y"
      shift 1
      ;;
    --node-id)
      NODE_ID="$2"
      shift 2
      ;;
    --port)
      HNODE_PORT="$2"
      shift 2
      ;;
    --host)
      HNODE_HOST="$2"
      shift 2
      ;;
    --api-host)
      HNODE_API_HOST="$2"
      shift 2
      ;;
    --api-port)
      HNODE_API_PORT="$2"
      shift 2
      ;;
    --zero-fees)
      ZERO_FEES=1
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
    --other-commands)
      shift 1
      OTHER_COMMANDS="$@"
      break  ;; 
    --help)
      echo "Usage: $0 --node-id <node id> [--testnet-magic <magic>] [--port <port>] [--host <host>] [--api-host <api-host>] [--api-port <api-port>] [--mainnet] [-d|--deploy-systemd] [-s|--stop-node]"
      exit 0
      ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
  esac
done

PERSISTENCE_DIR="${DATA_DIR}/persistence/${NODE_ID}"
mkdir -p "$PERSISTENCE_DIR" 

if [ -f "data/reference-scripts.json" ] && [ -s "data/reference-scripts.json" ]; then
  echo "Using reference script from data/reference-script.txt"
  REFERENCE_SCRIPTS=$(jq -r 'join(",")' data/reference-scripts.json)
else
  echo "data/reference-script.txt not found or empty; fetching based on NETWORK_FLAG..."
  case "$NETWORK_FLAG" in
    "--mainnet")
      REFERENCE_SCRIPTS=$(curl -s https://raw.githubusercontent.com/cardano-scaling/hydra/master/networks.json \
        | jq -r ".mainnet.\"${HYDRA_NODE_VERSION}\"")
      ;;
    "--testnet-magic 1"|"--testnet-magic=1")
      REFERENCE_SCRIPTS=$(curl -s https://raw.githubusercontent.com/cardano-scaling/hydra/master/networks.json \
        | jq -r ".preprod.\"${HYDRA_NODE_VERSION}\"")
      ;;
    "--testnet-magic 2"|"--testnet-magic=2")
      REFERENCE_SCRIPTS=$(curl -s https://raw.githubusercontent.com/cardano-scaling/hydra/master/networks.json \
        | jq -r ".preview.\"${HYDRA_NODE_VERSION}\"")
      ;;
    *)
      echo "Error: Unknown NETWORK_FLAG: $NETWORK_FLAG"
      exit 1
      ;;
  esac
fi

if [ -f "${DATA_DIR}/protocol-parameters.json" ]; then
  echo "protocol-parameters.json already exists in ${DATA_DIR}. Skipping query..."
else
  if [ "$ZERO_FEES" -eq 1 ]; then
    cardano-cli query protocol-parameters $NETWORK_FLAG --socket-path $CARDANO_NODE_SOCKET_PATH \
      | jq '.txFeeFixed = 0 | .txFeePerByte = 0 | .executionUnitPrices.priceMemory = 0 | .executionUnitPrices.priceSteps = 0' \
      > "${DATA_DIR}/protocol-parameters.json"
  else
    cardano-cli query protocol-parameters $NETWORK_FLAG --socket-path $CARDANO_NODE_SOCKET_PATH \
      > "${DATA_DIR}/protocol-parameters.json"
  fi
fi

peers_args=()               
cardano_verification_key_args=()
hydra_verification_key_args=()
LOCAL_HOST=$HNODE_HOST
LOCAL_PORT=$HNODE_PORT
LOCAL_API_HOST=$HNODE_API_HOST 
LOCAL_API_PORT=$HNODE_API_PORT  

while IFS= read -r peer_json; do
  peer_node_id=$(echo "$peer_json" | jq -r '.["node-id"]')
  peer_host=$(echo "$peer_json" | jq -r '.["node-host"]')
  peer_port=$(echo "$peer_json" | jq -r '.["node-port"]')
  peer_api_host=$(echo "$peer_json" | jq -r '.["api-host"]')
  peer_api_port=$(echo "$peer_json" | jq -r '.["api-port"]')
  peer_vkey_cardano=$(echo "$peer_json" | jq -r '.["vkey-cardano"]')
  peer_vkey_hydra=$(echo "$peer_json" | jq -r '.["vkey-hydra"]')
  
  if [ "$peer_node_id" = "$NODE_ID" ]; then
    LOCAL_HOST="$peer_host"
    LOCAL_PORT="$peer_port"
    LOCAL_API_HOST=$peer_api_host 
    LOCAL_API_PORT="$peer_api_port"
  else
    peers_args+=(--peer "${peer_host}:${peer_port}")
    cardano_verification_key_args+=(--cardano-verification-key "$peer_vkey_cardano")
    hydra_verification_key_args+=(--hydra-verification-key "$peer_vkey_hydra")
  fi
done < <(jq -c '.[]' "${DATA_DIR}/peers.json")

echo "  ${peers_args[@]}"
echo "  ${hydra_verification_key_args[@]}"

[[ "${STOP_NODE}" == "Y" ]] && stop_node

if [[ "${DEPLOY_SYSTEMD}" == "Y" ]]; then
  deploy_systemd && exit 0
  exit 2
fi

exec "${HNODEBIN}" \
  --node-id $NODE_ID \
  --persistence-dir $PERSISTENCE_DIR \
  --cardano-signing-key "${CREDENTIALS_DIR}/${NODE_ID}/${NODE_ID}-node.sk" \
  --hydra-signing-key "${CREDENTIALS_DIR}/${NODE_ID}/${NODE_ID}-hydra.sk" \
  --hydra-scripts-tx-id $REFERENCE_SCRIPTS \
  --ledger-protocol-parameters "${DATA_DIR}/protocol-parameters.json" \
  $NETWORK_FLAG \
  --node-socket $CARDANO_NODE_SOCKET_PATH \
  --api-host $LOCAL_API_HOST \
  --api-port $LOCAL_API_PORT \
  --host $LOCAL_HOST \
  --port $LOCAL_PORT \
  "${peers_args[@]}" \
  "${cardano_verification_key_args[@]}" \
  "${hydra_verification_key_args[@]}" \
  $OTHER_COMMANDS