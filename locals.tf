locals {
  # Proxmox
  node_name    = "pve01"
  datastore_id = "k3s-storage"
  bridge       = "vmbr0"

  # Network
  gateway     = "192.168.1.1"
  dns_servers = ["192.168.1.100", "8.8.8.8"]

  # Talos
  talos_version    = "v1.9.5"
  cluster_name     = "nase-dev-prod"
  control_plane_ip = "192.168.1.61"
  worker_ips       = ["192.168.1.62", "192.168.1.63"]
  all_ips          = concat([local.control_plane_ip], local.worker_ips)

  # API endpoint
  cluster_endpoint = "https://${local.control_plane_ip}:6443"
}
