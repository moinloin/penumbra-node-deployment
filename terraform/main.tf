data "digitalocean_ssh_key" "ssh_key" {
  name = var.ssh_key_name
}

resource "digitalocean_droplet" "penumbra_node" {
  image      = "ubuntu-22-04-x64"
  name       = "penumbra-node"
  region     = var.region
  size       = var.droplet_size
  ssh_keys   = [data.digitalocean_ssh_key.ssh_key.id]
  resize_disk = true
  user_data  = file("scripts/setup_node.sh")
}

resource "digitalocean_project_resources" "penumbra_resources" {
  project = var.do_project_id
  resources = [
    digitalocean_droplet.penumbra_node.urn,
    digitalocean_volume.penumbra_data.urn
  ]
}

resource "digitalocean_record" "penumbra_node" {
  count  = var.domain_name != "" ? 1 : 0
  domain = var.domain_name
  type   = "A"
  name   = "penumbra"
  value  = digitalocean_droplet.penumbra_node.ipv4_address
  ttl    = 300
}

resource "digitalocean_firewall" "penumbra_firewall" {
  name = "penumbra-firewall"
  droplet_ids = [digitalocean_droplet.penumbra_node.id]
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "26656"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "26657"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8080"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_volume" "penumbra_data" {
  region                  = var.region
  name                    = "penumbra-data"
  size                    = 100
  initial_filesystem_type = "ext4"
  description             = "Penumbra blockchain data"
}

resource "digitalocean_volume_attachment" "penumbra_data_attachment" {
  droplet_id = digitalocean_droplet.penumbra_node.id
  volume_id  = digitalocean_volume.penumbra_data.id
}
