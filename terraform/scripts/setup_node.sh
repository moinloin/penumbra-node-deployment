#!/bin/bash
# setup_node.sh - Script to set up a Penumbra node with reindexer capability

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
      - /var/run/postgresql:/var/run/postgresql
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

# Install dependencies
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
    clang \
    libclang-dev \
    llvm-dev \
    zlib1g-dev \
    libbz2-dev \
    libsnappy-dev \
    liblz4-dev \
    libzstd-dev \
    golang-go \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="${HOME}/.cargo/bin:${PATH}"

# Install pd and cometbft
RUN curl -sSfL -O https://github.com/penumbra-zone/penumbra/releases/latest/download/pd-x86_64-unknown-linux-gnu.tar.gz && \
    tar -xf pd-x86_64-unknown-linux-gnu.tar.gz && \
    mv pd-x86_64-unknown-linux-gnu/pd /usr/local/bin/ && \
    rm -rf pd-x86_64-unknown-linux-gnu pd-x86_64-unknown-linux-gnu.tar.gz

RUN curl -sSfL -O https://github.com/cometbft/cometbft/releases/download/v0.37.15/cometbft_0.37.15_linux_amd64.tar.gz && \
    tar -xf cometbft_0.37.15_linux_amd64.tar.gz && \
    mv cometbft /usr/local/bin/ && \
    rm -rf cometbft_0.37.15_linux_amd64.tar.gz

# Clone and build reindexer (with Go dependencies)
RUN git clone https://github.com/penumbra-zone/reindexer.git /opt/reindexer
WORKDIR /opt/reindexer
# Set up Go environment variables
ENV GOPATH=/root/go
ENV PATH="${GOPATH}/bin:${PATH}"
RUN go install golang.org/x/tools/cmd/stringer@latest
RUN cargo build --release && \
    cp target/release/penumbra-reindexer /usr/local/bin/

# Create penumbra user
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
    
    # Download the latest archive from artifacts.plinfra.net
    curl -O "$ARCHIVE_URL"
    ARCHIVE_FILE=$(basename "$ARCHIVE_URL")
    
    # Extract the archive to a temporary location
    echo "Extracting archive..."
    mkdir -p /tmp/archive
    tar -xzf "$ARCHIVE_FILE" -C /tmp/archive
    
    # Create a PostgreSQL database for events if it doesn't exist
    echo "Setting up PostgreSQL database..."
    # Since we're using the socket connection, we should be able to connect as postgres
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -c "CREATE DATABASE $POSTGRES_DB;" || true
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -c "CREATE DATABASE $REINDEX_DB;" || true
    
    # Create working directory for reindexing
    mkdir -p /tmp/regen
    
    # Run the reindexer to process the historical blocks
    echo "Running reindexer..."
    # First pass to process pre-upgrade blocks (you'll need to know the exact height)
    # This is just an example, adjust the stop-height based on actual upgrade points
    if [ -f "/tmp/archive/reindexer_archive.bin" ]; then
        penumbra-reindexer regen \
            --database-url "postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB?sslmode=disable" \
            --working-dir /tmp/regen \
            --archive-file "/tmp/archive/reindexer_archive.bin"
    else
        echo "No reindexer archive found, skipping reindexing"
    fi
    
    # After reindexing, copy blocks to our node directory
    if [ -d "/tmp/archive/cometbft" ]; then
        echo "Copying historical block data to node directory..."
        cp -r /tmp/archive/cometbft/* "$NETWORK_DATA/cometbft/"
    fi
    
    # Configure CometBFT to use kv indexer for events
    echo "Configuring CometBFT indexer to store events..."
    sed -i 's/indexer = ".*"/indexer = "kv"/' "$NETWORK_DATA/cometbft/config/config.toml"
    
    # Clean up
    rm -rf /tmp/regen /tmp/archive
    rm "$ARCHIVE_FILE"
    
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

service postgresql start
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD 'postgres';\""
echo "host    all             all             172.17.0.0/16           md5" >> /etc/postgresql/14/main/pg_hba.conf
echo "listen_addresses = '*'" >> /etc/postgresql/14/main/postgresql.conf
service postgresql restart

docker compose build
docker compose up -d

(crontab -l 2>/dev/null; echo "*/5 * * * * docker compose -f /opt/penumbra-node/docker-compose.yml ps | grep -q 'penumbra-node' || docker compose -f /opt/penumbra-node/docker-compose.yml up -d") | crontab -

echo "Penumbra node setup complete!"
