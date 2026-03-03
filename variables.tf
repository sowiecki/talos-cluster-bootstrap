variable "proxmox_api_token" {
  description = "Proxmox API token (format: USER@REALM!TOKENID=SECRET)"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key_path" {
  description = "Path to SSH private key for Proxmox root user. If null, ssh-agent is used."
  type        = string
  default     = null
}
