#!/bin/bash
# setup_node.sh - Script to set up Penumbra node with snapshot

set -e

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# Install required packages
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git wget lz4
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Set up storage with proper permissions
mkdir -p /mnt/penumbra-data/node
chmod -R 777 /mnt/penumbra-data  # More permissive for troubleshooting

# Create Docker setup directory
mkdir -p /opt/penumbra-node
cd /opt/penumbra-node

cat > init-node.sh << 'EOL'
#!/bin/bash
set -e

echo "Starting Penumbra node initialization..."

# Directory setup with proper permissions
mkdir -p /home/penumbra/.penumbra/network_data/node0/pd/rocksdb
mkdir -p /home/penumbra/.penumbra/network_data/node0/cometbft/config
mkdir -p /home/penumbra/.penumbra/network_data/node0/cometbft/data

# Reset any existing configuration
echo "Resetting any existing configurations..."
pd network unsafe-reset-all || true

# Join the network using Polkachu's RPC endpoint
echo "Joining the Penumbra network via Polkachu's RPC..."
pd network join \
  --moniker "penumbra-explorer-node" \
  --external-address "${EXTERNAL_ADDRESS}:26656" \
  https://penumbra-rpc.polkachu.com:26657 || true

# Fetch genesis.json directly from Polkachu using curl
echo "Fetching genesis.json from Polkachu..."
curl -s https://snapshots.polkachu.com/genesis/penumbra/genesis.json -o /home/penumbra/.penumbra/network_data/node0/cometbft/config/genesis.json

# Download Polkachu snapshot
echo "Attempting to download Penumbra snapshot from Polkachu..."
SNAPSHOT_URL=$(curl -s https://polkachu.com/tendermint_snapshots/penumbra | grep -o 'https://snapshots.polkachu.com/snapshots/penumbra/.*\.tar.lz4' | head -1)

if [ -n "$SNAPSHOT_URL" ]; then
  echo "Found snapshot URL: $SNAPSHOT_URL"
  curl -L $SNAPSHOT_URL -o /tmp/snapshot.tar.lz4

  # Extract snapshot
  echo "Extracting snapshot..."
  mkdir -p /tmp/snapshot
  lz4 -c -d /tmp/snapshot.tar.lz4 | tar -x -C /tmp/snapshot

  # Apply snapshot to node
  echo "Applying snapshot data to node..."
  cp -r /tmp/snapshot/data/* /home/penumbra/.penumbra/network_data/node0/cometbft/data/ || true

  # Clean up
  rm -rf /tmp/snapshot /tmp/snapshot.tar.lz4

  echo "Snapshot applied successfully."
else
  echo "Failed to find snapshot URL. Node may not sync correctly."
fi

# Make sure CometBFT uses KV indexer
echo "Configuring CometBFT to use KV indexer for ABCI events..."
if [ -f "/home/penumbra/.penumbra/network_data/node0/cometbft/config/config.toml" ]; then
  sed -i 's/indexer = ".*"/indexer = "kv"/' /home/penumbra/.penumbra/network_data/node0/cometbft/config/config.toml
else
  # Create a minimal config if it doesn't exist
  mkdir -p /home/penumbra/.penumbra/network_data/node0/cometbft/config
  echo '[tx_index]
indexer = "kv"' > /home/penumbra/.penumbra/network_data/node0/cometbft/config/config.toml
fi

# Set proper permissions for all files
echo "Setting proper permissions..."
chmod -R 777 /home/penumbra/.penumbra

echo "Node initialization complete."
EOL

chmod +x init-node.sh

# Create Docker Compose file with separate containers
cat > docker-compose.yml << 'EOL'
services:
  init:
    image: ghcr.io/penumbra-zone/penumbra:latest
    container_name: penumbra-init
    command: /init-node.sh
    environment:
      - EXTERNAL_ADDRESS=${external_address}
    volumes:
      - /mnt/penumbra-data/node:/home/penumbra/.penumbra/network_data/node0
      - ./init-node.sh:/init-node.sh
    user: "0:0"  # Run as root to avoid permission issues

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
    command: start --proxy_app tcp://pd:26658
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

# Get external IP
EXTERNAL_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)

# Update docker-compose file with external IP
sed -i "s/\${external_address}/$EXTERNAL_IP/g" docker-compose.yml

# Run initialization container
echo "Running initialization container..."
docker compose run --rm init

# Start the services
echo "Starting Penumbra node services..."
docker compose up -d pd cometbft

# Add cron job to ensure containers stay up
(crontab -l 2>/dev/null; echo "*/5 * * * * cd /opt/penumbra-node && docker compose ps | grep -q 'penumbra-pd' || docker compose up -d") | crontab -

echo "Penumbra node setup complete!"
echo "The node is set up to store ABCI events in the raw CometBFT database."
echo "You can check the node status with: docker logs penumbra-pd"
echo "You can check CometBFT status with: docker logs penumbra-cometbft"