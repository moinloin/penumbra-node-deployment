# Penumbra Node Setup: Progress and Troubleshooting

## Overview
This document tracks the progress, challenges, and solutions encountered when setting up a Penumbra node for blockchain event indexing. The primary goal was to establish a node that properly stores ABCI events in the raw CometBFT database.

## Requirements
* Penumbra node with proper ABCI event storage
* Genesis configuration with valid app_state
* Snapshot data to provide necessary historical blockchain information

## Challenges Encountered

### 1. Genesis File Issues
When attempting to join the network using various RPC endpoints, the generated genesis.json file was either:
* Missing entirely
* Missing the required app_state section
* Not properly formatted

**Error:**
```
Error: app_state is missing from genesis.json. Please provide a valid genesis file.
```

### 2. Consensus Keys Missing
When attempting to start the pd service after generating configs:

**Error:**
```
thread 'tokio-runtime-worker' panicked at /home/runner/.cargo/registry/src/index.crates.io-6f17d22bba15001f/penumbra/crates/core/component/stake/src/component/epoch_handler.rs:430:14:
current consensus keys must be present
```

This indicates that the node was bootstrapped from a post-upgrade peer without applying necessary snapshot data.

### 3. RPC Endpoint Connectivity
Attempted to use various RPC endpoints:
* https://rpc.penumbra.zone:26657 (DNS resolution issues)
* http://grpc.penumbra.silentvalidator.com:26657 (Generated invalid genesis)
* https://penumbra-rpc.polkachu.com (Recommended by Penumbra team and worked successfully)

### 4. Large Snapshot Management
The Penumbra snapshot is extremely large (over 100GB):
* Download interruptions due to connectivity issues
* Storage requirements exceeding default VM allocations
* Need for download resumption capabilities

### 5. Node Persistence
Ensuring the node continues running after SSH disconnections:
* Process termination when terminal closes
* Need for background processes that persist

## Solutions Implemented

### 1. Direct Genesis File Download
Bypassed the generation issue by directly downloading the genesis file from Polkachu:

```bash
curl -s https://snapshots.polkachu.com/genesis/penumbra/genesis.json \
  -o ~/.penumbra/network_data/node0/cometbft/config/genesis.json
```

### 2. Snapshot Application
Downloaded and applied the Polkachu snapshot to resolve the consensus keys issue:

```bash
# Download specific snapshot with resume capability
cd /mnt/penumbra_data  # Using mounted volume for storage
tmux new-session -s download
wget -c https://snapshots.polkachu.com/snapshots/penumbra/penumbra_latest.tar.lz4

# Extract and apply
lz4 -dc penumbra_latest.tar.lz4 | tar -xf - -C ~/.penumbra/network_data/node0/
```

### 3. Initial KV Indexer Configuration
First ensured CometBFT was configured to properly store ABCI events in the local key-value store:

```bash
# Configure KV indexer
CONFIG_FILE=~/.penumbra/network_data/node0/cometbft/config/config.toml
sed -i 's/indexer = "null"/indexer = "kv"/' $CONFIG_FILE
```

This allowed the node to start syncing and storing events locally.

### 4. Upgrade to PostgreSQL for Explorer Support
After confirming basic functionality, upgraded to Digital Ocean PostgreSQL for better explorer support:

```bash
# Create database on Digital Ocean PostgreSQL
# Applied CometBFT schema to the database
psql -d $DATABASE_NAME -f schema.sql

# Reconfigure CometBFT to use PostgreSQL
CONFIG_FILE=~/.penumbra/network_data/node0/cometbft/config/config.toml
sed -i 's/indexer = "kv"/indexer = "psql"/' $CONFIG_FILE
sed -i 's/#psql-conn = ""/psql-conn = "postgresql:\/\/username:password@host:port\/database?sslmode=require"/' $CONFIG_FILE

# Verified events were being stored properly
psql -d $DATABASE_NAME -c "SELECT height FROM blocks ORDER BY height DESC LIMIT 10;"
```

Using Digital Ocean's managed PostgreSQL service provided:
- Better reliability and automatic backups
- Simplified database management
- Higher performance for the Explorer backend queries
- Required format for the PK Labs explorer backend


### 4. Process Management with tmux
Used tmux to ensure processes continue running after SSH disconnection:

```bash
# Start a tmux session
tmux new-session -s penumbra

# Start CometBFT
cometbft start --home $HOME/.penumbra/network_data/node0/cometbft

# Split screen and start pd in second pane (Ctrl+B, %)
pd start --home $HOME/.penumbra/network_data/node0

# Detach from session (Ctrl+B, d)
```

### 5. Reverse Proxy Configuration
Set up Caddy as a reverse proxy to expose the RPC endpoint:

```
proofofconcept.ch {
    reverse_proxy http://192.168.15.231:26657
}
```

## Current Status
The node setup addresses the primary requirement of storing ABCI events in a database accessible to the explorer:

1. Direct download of a valid genesis.json
2. Application of a blockchain snapshot from Polkachu
3. Initial configuration with KV indexer for basic functionality
4. Upgrade to PostgreSQL indexer using Digital Ocean managed database for explorer support
5. Background process management with tmux
6. Public access via reverse proxy

The node is now:
- Successfully syncing with the Penumbra network
- Properly storing ABCI events in the PostgreSQL database
- Successfully connected to the PK Labs Penumbra Explorer backend (https://github.com/pk-labs/penumbra-explorer-backend)
- Serving data to the explorer through the established database connection

Currently working on implementing the reindexing functionality to provide historical data access.

## Next Steps
1. Complete the implementation of the reindexer component for historical data processing (in progress)
2. Set up monitoring with Prometheus/Grafana

## References
* [Penumbra Network Join Documentation](https://guide.penumbra.zone/node/pd)
* [Polkachu Snapshots](https://snapshots.polkachu.com/snapshots/penumbra)
* [Penumbra Reindexer](https://github.com/penumbra-zone/reindexer)
