output "droplet_ip" {
  description = "Public IP of the Penumbra node"
  value       = digitalocean_droplet.penumbra_node.ipv4_address
}

output "node_url" {
  description = "URL to access the Penumbra node"
  value       = var.domain_name != "" ? "https://${var.domain_name}/penumbra" : "http://${digitalocean_droplet.penumbra_node.ipv4_address}:26657"
}

output "ssh_command" {
  description = "Command to SSH into the droplet"
  value       = "ssh root@${digitalocean_droplet.penumbra_node.ipv4_address}"
}
