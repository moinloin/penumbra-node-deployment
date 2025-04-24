#!/bin/bash
# setup_node.sh - Script to set up Penumbra node with separate containers

set -e

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

mkdir -p /mnt/penumbra-data/node
chown -R 1000:1000 /mnt/penumbra-data
sudo chown -R 100:1000 /mnt/penumbra-data/node/cometbft

mkdir -p /opt/penumbra-node
cd /opt/penumbra-node

mkdir -p /mnt/penumbra-data/node/cometbft/config
cat > /mnt/penumbra-data/node/cometbft/config/genesis.json << 'EOF'
{
  "genesis_time": "2023-01-01T00:00:00Z",
  "chain_id": "penumbra-testnet",
  "initial_height": "1",
  "consensus_params": {
    "block": {
      "max_bytes": "22020096",
      "max_gas": "-1",
      "time_iota_ms": "1000"
    },
    "evidence": {
      "max_age_num_blocks": "100000",
      "max_age_duration": "172800000000000",
      "max_bytes": "1048576"
    },
    "validator": {
      "pub_key_types": ["ed25519"]
    },
    "version": {}
  },
  "app_state": {
    "content": {
      "chain_params": {
        "chain_id": "penumbra-testnet",
        "epoch_duration": 86400
      },
      "allocations": []
    }
  }
}
EOF

mkdir -p /mnt/penumbra-data/node/cometbft/config
cat > /mnt/penumbra-data/node/cometbft/config/config.toml << 'EOF'
# This is a TOML config file.
# For more information, see https://github.com/toml-lang/toml

# CometBFT config with KV indexer for storing ABCI events
[tx_index]
indexer = "kv"
EOF

mkdir -p /mnt/penumbra-data/node/pd/rocksdb
chown -R 1000:1000 /mnt/penumbra-data/node

cat > docker-compose.yml << 'EOL'
version: '3.8'

services:
  pd:
    image: ghcr.io/penumbra-zone/penumbra:latest
    container_name: penumbra-pd
    command: pd start --abci-bind 0.0.0.0:26658 --grpc-bind 0.0.0.0:8080 --cometbft-addr http://cometbft:26657
    volumes:
      - /mnt/penumbra-data/node:/home/penumbra/.penumbra/network_data/node0
    ports:
      - "8080:8080"
      - "26658:26658"
    restart: unless-stopped
    user: "1000:1000"

  cometbft:
    image: cometbft/cometbft:v0.37.15
    container_name: penumbra-cometbft
    command: start --home /cometbft
    depends_on:
      - pd
    volumes:
      - /mnt/penumbra-data/node/cometbft:/cometbft
    environment:
      - CMTHOME=/cometbft
    ports:
      - "26656:26656"
      - "26657:26657"
    restart: unless-stopped
    user: "100:1000"
EOL

docker compose up -d

(crontab -l 2>/dev/null; echo "*/5 * * * * docker compose -f /opt/penumbra-node/docker-compose.yml ps | grep -q 'penumbra-pd' || docker compose -f /opt/penumbra-node/docker-compose.yml up -d") | crontab -

echo "Penumbra node setup complete!"
