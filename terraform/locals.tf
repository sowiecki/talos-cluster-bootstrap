locals {
  node_name        = "pve01"
  proxmox_nodes    = ["pve01", "pve02", "pve03", "pve04"]
  bridge           = "vmbr0"
  gateway          = "192.168.1.1"
  dns_servers      = ["192.168.1.100", "8.8.8.8"]
  talos_version    = "v1.13.0"
  cluster_name     = "nase-dev-prod"
  control_plane_ip = "192.168.1.61"
  worker_ips       = ["192.168.1.62", "192.168.1.63", "192.168.1.64"]
  all_ips          = concat([local.control_plane_ip], local.worker_ips)
  cluster_endpoint = "https://${local.control_plane_ip}:6443"
  kubeconfig_path  = abspath("${path.module}/kubeconfig")

  # TrueNAS – for the CSI driver
  truenas_nfs_server = "192.168.1.32"
  truenas_pool       = "Uldaman"
  truenas_dataset    = "k8s"
}
