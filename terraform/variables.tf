variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "fra1"
}

variable "droplet_size" {
  description = "Droplet size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "ssh_key_name" {
  description = "SSH key name in DigitalOcean"
  type        = string
}

variable "node_url" {
  description = "Penumbra node URL to connect to"
  type        = string
  default     = "https://rpc.penumbra.zone:26657"
}

variable "moniker" {
  description = "Moniker for the Penumbra node"
  type        = string
  default     = "penumbra-explorer-node"
}

variable "fetch_history" {
  description = "Whether to fetch and reindex historical data"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain name for the Penumbra node"
  type        = string
  default     = ""
}

variable "do_project_id" {
  description = "DigitalOcean project ID"
  type        = string
}

