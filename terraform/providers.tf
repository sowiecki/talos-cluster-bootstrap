terraform {
  required_providers {
    proxmox    = { source = "bpg/proxmox", version = "~> 0.96" }
    talos      = { source = "siderolabs/talos", version = "~> 0.10" }
    time       = { source = "hashicorp/time", version = "~> 0.12" }
    local      = { source = "hashicorp/local", version = "~> 2.5" }
    null       = { source = "hashicorp/null", version = "~> 3.2" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.23" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.1.65:8006/"
  api_token = var.proxmox_api_token
  insecure  = true
  ssh {
    agent       = var.proxmox_ssh_private_key_path == null ? true : false
    username    = "root"
    private_key = var.proxmox_ssh_private_key_path != null ? file(var.proxmox_ssh_private_key_path) : null
  }
}

provider "talos" {}

provider "kubernetes" {
  config_path = local.kubeconfig_path
  host        = local.kubeconfig_yaml.clusters[0].cluster.server
}

provider "helm" {
  kubernetes {
    config_path = local.kubeconfig_path
  }
}
