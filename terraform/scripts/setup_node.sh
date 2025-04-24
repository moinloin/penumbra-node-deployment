#!/bin/bash
set -e

apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

apt-get install -y \
    build-essential \
    curl \
    git \
    jq \
    ca-certificates \
    libssl-dev \
    pkg-config \
    postgresql \
    postgresql-contrib

mkdir -p /mnt/penumbra-data
echo '/dev/disk/by-id/scsi-0DO_Volume_penumbra-data /mnt/penumbra-data ext4 defaults,nofail,discard 0 2' >> /etc/fstab
mount -a
mkdir -p /mnt/penumbra-data/penumbra
chown 1000:1000 /mnt/penumbra-data/penumbra

mkdir -p /opt/penumbra-node
cd /opt/penumbra-node

cat > docker-compose.yml << 'EOL'
version: '3.8'

services:
  penumbra-node:
    build: .
    container_name: penumbra-node
    environment:
      - NODE_URL=${node_url}
      - MONIKER=${moniker}
      - EXTERNAL_ADDRESS=${external_address}:26656
      - FETCH_HISTORY=${fetch_history}
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=penumbra
      - REINDEX_DB=penumbra_indexed
    volumes:
      - /mnt/penumbra-data/penumbra:/home/penumbra/.penumbra
    ports:
      - "26656:26656"
      - "26657:26657"
      - "8080:8080"
      - "443:443"
    restart: unless-stopped
EOL

cat > Dockerfile << 'EOL'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root
ENV PATH="${PATH}:/usr/local/bin"

RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    jq \
    ca-certificates \
    libssl-dev \
    pkg-config \
    wget \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="${HOME}/.cargo/bin:${PATH}"

RUN curl -sSfL -O https://github.com/penumbra-zone/penumbra/releases/latest/download/pd-x86_64-unknown-linux-gnu.tar.gz && \
    tar -xf pd-x86_64-unknown-linux-gnu.tar.gz && \
    mv pd-x86_64-unknown-linux-gnu/pd /usr/local/bin/ && \
    rm -rf pd-x86_64-unknown-linux-gnu pd-x86_64-unknown-linux-gnu.tar.gz

RUN curl -sSfL -O https://github.com/cometbft/cometbft/releases/download/v0.37.15/cometbft_0.37.15_linux_amd64.tar.gz && \
    tar -xf cometbft_0.37.15_linux_amd64.tar.gz && \
    mv cometbft /usr/local/bin/ && \
    rm -rf cometbft_0.37.15_linux_amd64.tar.gz

RUN git clone https://github.com/penumbra-zone/reindexer.git /opt/reindexer
WORKDIR /opt/reindexer
RUN cargo build --release && \
    cp target/release/reindexer /usr/local/bin/

RUN useradd -m -d /home/penumbra penumbra -s /bin/bash

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/penumbra
RUN chown -R penumbra:penumbra /home/penumbra

USER penumbra

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EOL

cat > entrypoint.sh << 'EOL'
#!/bin/bash
set -e

export PATH="$PATH:/usr/local/bin"
NODE_HOME="/home/penumbra/.penumbra"
NETWORK_DATA="$NODE_HOME/network_data/node0"
ARCHIVE_URL="https://artifacts.plinfra.net/penumbra-1/penumbra-node-archive-latest.tar.gz"
NODE_URL="${NODE_URL:-https://rpc.penumbra.zone:26657}"
MONIKER="${MONIKER:-penumbra-explorer-node}"
EXTERNAL_ADDRESS="${EXTERNAL_ADDRESS:-}"
FETCH_HISTORY="${FETCH_HISTORY:-false}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-penumbra}"
REINDEX_DB="${REINDEX_DB:-penumbra_indexed}"

mkdir -p "$NETWORK_DATA/pd/rocksdb"

if [ ! -f "$NETWORK_DATA/cometbft/config/genesis.json" ]; then
    echo "Initializing Penumbra node..."
    
    pd network unsafe-reset-all

    if [ -n "$EXTERNAL_ADDRESS" ]; then
        pd network join \
            --moniker "$MONIKER" \
            --external-address "$EXTERNAL_ADDRESS" \
            "$NODE_URL"
    else
        pd network join \
            --moniker "$MONIKER" \
            "$NODE_URL"
    fi
    
    if [ ! -s "$NETWORK_DATA/cometbft/config/genesis.json" ]; then
        echo "Genesis file is missing or empty. Please check NODE_URL."
        exit 1
    fi
    
    if ! grep -q "\"app_state\"" "$NETWORK_DATA/cometbft/config/genesis.json"; then
        echo "app_state is missing from genesis.json. Please provide a valid genesis file."
        exit 1
    fi
    
    echo "Node initialization completed successfully."
fi

if [ "$FETCH_HISTORY" = "true" ]; then
    echo "Fetching historical data..."
    
    curl -O "$ARCHIVE_URL"
    ARCHIVE_FILE=$(basename "$ARCHIVE_URL")
    
    echo "Extracting archive..."
    tar -xzf "$ARCHIVE_FILE" -C "$NETWORK_DATA"
    rm "$ARCHIVE_FILE"
    
    echo "Configuring CometBFT indexer..."
    sed -i 's/indexer = ".*"/indexer = "kv"/' "$NETWORK_DATA/cometbft/config/config.toml"
    
    echo "Historical data processing completed."
else
    echo "Skipping historical data processing."
fi

echo "Ensuring CometBFT is configured to store ABCI events..."
sed -i 's/indexer = ".*"/indexer = "kv"/' "$NETWORK_DATA/cometbft/config/config.toml"

echo "Starting pd..."
pd start &
PD_PID=$!

sleep 10

echo "Starting CometBFT..."
cometbft start --home "$NETWORK_DATA/cometbft" &
COMETBFT_PID=$!

echo "Penumbra node is running. Press Ctrl+C to stop."
wait $PD_PID $COMETBFT_PID
EOL

chmod +x entrypoint.sh

EXTERNAL_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)

sed -i "s/\${external_address}/$EXTERNAL_IP/" docker-compose.yml
sed -i "s/\${node_url}/${node_url}/" docker-compose.yml
sed -i "s/\${moniker}/${moniker}/" docker-compose.yml
sed -i "s/\${fetch_history}/${fetch_history}/" docker-compose.yml

docker compose build
docker compose up -d

(crontab -l 2>/dev/null; echo "*/5 * * * * docker compose -f /opt/penumbra-node/docker-compose.yml ps | grep -q 'penumbra-node' || docker compose -f /opt/penumbra-node/docker-compose.yml up -d") | crontab -

echo "Penumbra node setup complete!"
