#!/bin/bash

set -e

echo "=== Penumbra Node Setup ==="

echo "Installing required packages..."
apt-get update
apt-get install -y git git-lfs lz4

echo "Cloning Penumbra repository..."
PENUMBRA_VERSION="v1.0.1"
git clone --branch $PENUMBRA_VERSION https://github.com/penumbra-zone/penumbra

echo "Setting up systemd services..."
cp penumbra/deployments/systemd/penumbra.service penumbra/deployments/systemd/cometbft.service /etc/systemd/system/

echo "Installing pd..."
curl -sSfL -O https://github.com/penumbra-zone/penumbra/releases/latest/download/pd-x86_64-unknown-linux-gnu.tar.gz
tar -xf pd-x86_64-unknown-linux-gnu.tar.gz
sudo mv pd-x86_64-unknown-linux-gnu/pd /usr/local/bin/
echo "pd version: $(pd --version)"

echo "Installing CometBFT..."
wget -O /tmp/cometbft.tar.gz https://github.com/cometbft/cometbft/releases/download/v0.37.15/cometbft_0.37.15_linux_amd64.tar.gz
tar -xzf /tmp/cometbft.tar.gz -C /tmp
sudo mv /tmp/cometbft /usr/local/bin/
chmod +x /usr/local/bin/cometbft

echo "Creating penumbra user..."
useradd -m -d /home/penumbra penumbra -s /bin/bash

echo "Setting up network configuration..."
read -p "Enter your node moniker: " MONIKER
EXTERNAL_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)

su - penumbra -c "pd network join \
  --moniker \"${MONIKER}\" \
  --external-address \"${EXTERNAL_IP}:26656\" \
  https://penumbra-rpc.polkachu.com"

echo "Downloading and applying Penumbra snapshot..."
cat > /home/penumbra/apply_snapshot.sh << 'EOL'
#!/bin/bash
set -e

echo "Downloading snapshot..."
wget -O penumbra_snapshot.tar.lz4 https://snapshots.polkachu.com/snapshots/penumbra/penumbra_$(curl -s https://snapshots.polkachu.com/snapshots/penumbra/ | grep -o 'penumbra_[0-9]*.tar.lz4' | sort -r | head -1 | cut -d '_' -f 2 | cut -d '.' -f 1).tar.lz4 --inet4-only

sudo service pd stop || true
sudo service cometbft stop || true

if [ -f "$HOME/.penumbra/network_data/node0/cometbft/data/priv_validator_state.json" ]; then
  echo "Backing up priv_validator_state.json..."
  cp $HOME/.penumbra/network_data/node0/cometbft/data/priv_validator_state.json $HOME/.penumbra/network_data/node0/cometbft/priv_validator_state.json.backup
fi

echo "Resetting CometBFT data..."
cometbft unsafe-reset-all --home $HOME/.penumbra/network_data/node0/cometbft --keep-addr-book

echo "Resetting pd data..."
rm -rf $HOME/.penumbra/network_data/node0/pd/rocksdb

echo "Applying snapshot..."
lz4 -c -d penumbra_snapshot.tar.lz4 | tar -x -C $HOME/.penumbra/network_data/node0/

if [ -f "$HOME/.penumbra/network_data/node0/cometbft/priv_validator_state.json.backup" ]; then
  echo "Restoring priv_validator_state.json..."
  cp $HOME/.penumbra/network_data/node0/cometbft/priv_validator_state.json.backup $HOME/.penumbra/network_data/node0/cometbft/data/priv_validator_state.json
fi

rm -v penumbra_snapshot.tar.lz4

echo "Snapshot applied successfully"
EOL

chmod +x /home/penumbra/apply_snapshot.sh
chown penumbra:penumbra /home/penumbra/apply_snapshot.sh
su - penumbra -c "/home/penumbra/apply_snapshot.sh"

echo "Starting Penumbra services..."
systemctl start penumbra
systemctl start cometbft

echo "Checking service status..."
systemctl status pd
systemctl status cometbft

echo "Penumbra node setup complete!"
echo "You can check the node status with: systemctl status penumbra"
echo "You can check CometBFT status with: systemctl status cometbft"
echo "View logs with: journalctl -u penumbra -f"
