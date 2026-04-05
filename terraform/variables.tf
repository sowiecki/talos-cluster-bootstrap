variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key_path" {
  description = "Path to SSH private key for Proxmox"
  type        = string
  default     = null
}

variable "truenas_ssh_private_key_path" {
  description = "Path to SSH private key for TrueNAS root user"
  type        = string
  default     = "/home/nase/.ssh/truenas-csi"
}

variable "truenas_api_key" {
  description = "API key for TrueNAS (generate in Settings → API Keys)"
  type        = string
  sensitive   = true
}
