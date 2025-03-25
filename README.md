# Hydra scripts

This repository is meant to speed up the process of creating multiple nodes with peers for the same head, which can speed up the development proccess when you need to manage multiple nodes. This is not in any case a replacement for the standard process, which you should at least run through once to understand what is going on:

- [Hydra Documentation](https://hydra.family/head-protocol/docs)

## Prerequisites

1. [Cardano Node](https://github.com/IntersectMBO/cardano-node/releases)
2. [Hydra Node](https://github.com/cardano-scaling/hydra/releases)

## Environment variables

Scripts need these environment variables to be defined:

- `HYDRA_NODE_VERSION` - version from [here](https://github.com/cardano-scaling/hydra/releases)
- `CARDANO_NODE_SOCKET_PATH`
- `HNODEBIN` - directory of binary executable for hydra node

## Scripts

### 1. _hydra-node.sh_

Main script for creating the hydra node. It will fetch protocol parameters, if not provided in the data folder:

- _data/protocol-parameters.json_

| Parameter                               | Description                                                                                               |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `--node-id <node-id>`                   | Node Id                                                                                                   |
| `--testnet-magic <number> or --mainnet` | Choose the network magic                                                                                  |
| `--deposit-deadline <number>`           | Deposit deadline for incemental commits                                                                   |
| `-s, --stop-node`                       | Stop the service                                                                                          |
| `--zero-fees`                           | Set fees to zero in the head                                                                              |
| `-d, --deploy-systemd`                  | Deploy as systemd                                                                                         |
| `-s, --stop-node`                       | Stop the service                                                                                          |
| all other paramters from hydra-node     | You can pass parameters defined in the [official documentation](https://github.com/cardano-scaling/hydra) |

### 2. _publish-reference-scripts.sh_

Script for publishing reference scripts on chain that are needed for the hydra node creation. To publish a script, you should have enough ADA on the address from signing key to cover the costs (~30ADA). It saves reference script tx ids into: **_data/reference-scripts.json_**

**Note: This script is essential if you are creating a hydra node on the private network ([yaci-devkit](https://github.com/bloxbean/yaci-devkit))**

| Parameter                               | Description              |
| --------------------------------------- | ------------------------ |
| `--node-id <node-id>`                   | Node Id                  |
| `--testnet-magic <number> or --mainnet` | Choose the network magic |
| `--signing-key-file <path>`             | Path to the signing key  |

### 3. _generate-credentials.sh_

Script for generating node, hydra credentials (adds peers if specified). It saves the keys into: **_data/credentials/{node-id}_**
You can also add credentials manually to the:

- _data/credentials/{node-id}/{node-id}-{hydra, node}.{sk, vk}_

| Parameter                                             | Description                                  |
| ----------------------------------------------------- | -------------------------------------------- |
| `--node-id <node-id>`                                 | Node Id                                      |
| `--generate-wallet`                                   | Generate wallet (funds account) for the node |
| `--add-peer <host>:<node-port>:<api-host>:<api-port>` | Adding credentials to **_peers.json_**       |
| `--testnet-magic <number> or --mainnet`               | Choose the network magic                     |

## Example usage:

### Preprod:

1. Change env file if needed, define `CARDANO_NODE_SOCKET_PATH`, `HNODEBIN` if not defined
2. Run `generate-credentials.sh --node-id vlad --add-peer 127.0.0.1:5001:127.0.0.1:4001`
3. [Fund](https://docs.cardano.org/cardano-testnets/tools/faucet) the address in **_data/vlad/vlad-node.addr_**
4. If you want to add more peers: repeat steps 2 - 3 **(diffetent ports, hosts and node-ids)** until you are satisfied
5. Run `hydra-node.sh --node-id vlad`
6. If you have peers specified: repeat step 5 **(different node-ids)** to run your peer nodes

### Private network:

1. Change env file if needed, define `CARDANO_NODE_SOCKET_PATH`, `HNODEBIN` if not defined
2. Don't forget to change `--testnet-magic` in the env file to your number
3. Run `generate-credentials.sh --node-id vlad --add-peer 127.0.0.1:5001:127.0.0.1:4001`
4. Fund the address in **_data/vlad/vlad-node.addr_**
5. If you want to add more peers: repeat steps 3 - 4 **(diffetent ports, hosts and node-ids)** until you are satisfied
6. Run `publish-reference-scripts.sh --node-id vlad`
7. Run `hydra-node.sh --node-id vlad`
8. If you have peers specified: repeat step 7 **(different node-ids)** to run your peer nodes

## Notes

1. [Why peers cant be added on the fly (yet)](https://github.com/cardano-scaling/hydra/issues/240)
2. [Blockfrost for hydra (WIP)](https://github.com/cardano-scaling/hydra/issues/1305)
3. [MeshJs SDK for hydra](https://meshjs.dev/providers/hydra)
4. [Why multiple heads per node are not available (yet)](https://github.com/cardano-scaling/hydra/issues/383)
