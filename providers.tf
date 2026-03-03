terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.96"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.1.65:8006/"
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent    = true
    username = "root"
  }
}

provider "talos" {}
