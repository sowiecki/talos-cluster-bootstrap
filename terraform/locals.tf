locals {
  # Use the external IPs (routable from the host network) + public fallback
  dns_servers = [
    # dns.nase.dev
    "192.168.1.30",

    # dns2.nase.dev
    "192.168.1.29",

    "1.1.1.1"
  ]

  node_name = "pve01"
  proxmox_nodes = [
    # M80Q
    "pve01",
    "pve02",
    "pve03",

    # M920T
    "pve04",

    # AMD Ryzen 5 5600G
    "pve05"
  ]
  bridge           = "vmbr0"
  gateway          = "192.168.1.1"
  talos_version    = "v1.13.0"
  cluster_name     = "nase-dev-prod"
  control_plane_ip = "192.168.1.61" # on pve01, host IP is 192.168.1.65
  worker_ips = [
    "192.168.1.62", # on pve02, host IP is 192.168.1.66
    "192.168.1.63", # on pve03, host IP is 192.168.1.67
    "192.168.1.64", # on pve04, host IP is 192.168.1.68
    "192.168.1.71"  # on pve05, host IP is 192.168.1.69
  ]

  # Index-aligned with local.worker_ips.
  # Reflects the physical CPU count of each Proxmox host.
  worker_cpu_cores = [
    10, # pve02
    10, # pve03
    6,  # pve04
    12  # pve05
  ]

  # Index-aligned with local.worker_ips.
  worker_class = [
    "standard",   # pve02
    "standard",   # pve03
    "standard",   # pve04
    "performance" # pve05
  ]

  # Index-aligned with local.worker_ips.
  worker_hardware = [
    { cores = 10, memory = 14000 }, # pve02
    { cores = 10, memory = 14000 }, # pve03
    { cores = 6, memory = 14000 },  # pve04
    { cores = 12, memory = 20000 }, # pve05
  ]

  # Index-aligned with local.worker_ips.
  # 109 is the Proxmox backup server so it is deliberately skipped
  worker_vm_ids = [106, 107, 108, 110]

  all_ips          = concat([local.control_plane_ip], local.worker_ips)
  cluster_endpoint = "https://${local.control_plane_ip}:6443"
  kubeconfig_path  = abspath("${path.module}/kubeconfig")

  # TrueNAS configuration for the CSI driver
  truenas_nfs_server = "192.168.1.32"
  truenas_pool       = "Uldaman"
  truenas_dataset    = "k8s"

  worker_node_labels = {
    standard    = "node-class=standard"
    performance = "node-class=performance"
  }

  # Extra kernel tuning only worth it on pve05
  performance_sysctls = {
    "net.netfilter.nf_conntrack_max" = "1048576"
    "net.core.netdev_max_backlog"    = "5000"
  }
}
