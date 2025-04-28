# Penumbra Node on DigitalOcean

This repository provides Terraform configurations to deploy a Penumbra node on DigitalOcean. It automatically sets up a full node with the latest snapshot, configures all necessary services, and provides easy management.

## Features

- One-click deployment of a Penumbra node on DigitalOcean
- Automatic provisioning of a 100GB volume for blockchain data
- Firewall configuration with only the required ports open
- DNS record creation (optional)
- Systemd service setup for both pd and CometBFT
- Automatic snapshot download and application
- Validator state backup and restore during updates

## Requirements

- [Terraform](https://www.terraform.io/downloads.html) installed locally
- DigitalOcean API token
- SSH key already added to your DigitalOcean account
- A domain name (optional, for HTTPS support)

## Deployment Instructions

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/penumbra-digitalocean.git
   cd penumbra-digitalocean
   ```

2. Create a `terraform.tfvars` file with your variables:
   ```hcl
   do_token = "your_digitalocean_api_token"
   ssh_key_name = "your_ssh_key_name"
   region = "fra1"  # or any other DO region
   droplet_size = "s-2vcpu-4gb"
   domain_name = "example.com"  # optional
   do_project_id = "your_project_id"
   moniker = "your-node-name"
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Apply the Terraform configuration:
   ```bash
   terraform apply
   ```

5. After completion, you'll see outputs with your node's IP address and connection details.

## Resource Configuration

This deployment creates:
- Ubuntu 22.04 droplet with the specified size
- 100GB volume for blockchain data
- Firewall with ports 22 (SSH), 26656 (P2P), 26657 (RPC), 8080 (gRPC), and 443 (HTTPS)
- DNS record (if a domain is provided)

## Maintenance

SSH into your node using the provided SSH command from the outputs:
```bash
ssh root@your_droplet_ip
```

- Check node status: `systemctl status penumbra` or `systemctl status cometbft`
- View logs: `journalctl -u penumbra -f` or `journalctl -u cometbft -f`
- Restart services: `systemctl restart penumbra cometbft`

## Customization

You can customize the deployment by modifying:
- `variables.tf`: Change default values for droplet size, region, etc.
- `main.tf`: Adjust resources or add additional configurations
- `scripts/setup_node.sh`: Modify the node setup script

## Troubleshooting

If you encounter issues:

1. Check the logs: `journalctl -u penumbra -e`
2. Ensure services are running: `systemctl status penumbra cometbft`
3. Verify connectivity: `curl -s http://localhost:26657/status`
4. Check the attached volume: `df -h`

## Updating the Node

To update your node to a newer version:

1. SSH into the droplet
2. Stop the services: `systemctl stop penumbra cometbft`
3. Update pd and restart: 
   ```bash
   curl -sSfL -O https://github.com/penumbra-zone/penumbra/releases/latest/download/pd-x86_64-unknown-linux-gnu.tar.gz
   tar -xf pd-x86_64-unknown-linux-gnu.tar.gz
   sudo mv pd-x86_64-unknown-linux-gnu/pd /usr/local/bin/
   systemctl start penumbra cometbft
   ```

## Destroy Infrastructure

To remove all created resources:
```bash
terraform destroy
```

## Acknowledgments

- [Penumbra Zone](https://penumbra.zone/) for creating the Penumbra protocol
- [Polkachu](https://polkachu.com/) for providing snapshots and RPC endpoints
- [DigitalOcean](https://www.digitalocean.com/) for cloud infrastructure
