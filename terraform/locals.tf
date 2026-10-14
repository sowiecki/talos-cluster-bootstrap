locals {
  dns_servers = [
    "192.168.1.30",
    "192.168.1.29",
    "1.1.1.1",
  ]

  bridge           = "vmbr0"
  gateway          = "192.168.1.1"
  talos_version    = "v1.13.0"
  cluster_name     = "nase-dev-prod"
  control_plane_ip = "192.168.1.61"

  kubeconfig_path = abspath("${path.module}/kubeconfig")

  truenas_nfs_server = "192.168.1.32"
  truenas_pool       = "Uldaman"
  truenas_dataset    = "k8s"

  # ----------------------------------------------------------------------
  # Worker node specs.
  #
  # talos_version_override: set when a worker needs a different Talos
  # version than the cluster default. worker-5 needs v1.13.3+ for the
  # iscsi-tools path fix that Longhorn requires. All other workers leave
  # this null so they continue using local.talos_version unchanged.
  # ----------------------------------------------------------------------
  workers = {
    worker-1 = {
      proxmox_node   = "pve02"
      ip             = "192.168.1.62"
      vm_id          = 106
      mac_address    = "BC:24:11:00:00:62"
      cores          = 10
      memory         = 14000
      os_disk_size   = 950
      node_class     = "standard"
      kubelet_args   = {}
      sysctls        = {}
      longhorn_disks = {}
      talos_version_override = null
    }
    worker-2 = {
      proxmox_node   = "pve03"
      ip             = "192.168.1.63"
      vm_id          = 107
      mac_address    = "BC:24:11:00:00:63"
      cores          = 10
      memory         = 14000
      os_disk_size   = 950
      node_class     = "standard"
      kubelet_args   = {}
      sysctls        = {}
      longhorn_disks = {}
      talos_version_override = null
    }
    worker-3 = {
      proxmox_node   = "pve04"
      ip             = "192.168.1.64"
      vm_id          = 108
      mac_address    = "BC:24:11:00:00:64"
      cores          = 6
      memory         = 14000
      os_disk_size   = 950
      node_class     = "standard"
      kubelet_args   = {}
      sysctls        = {}
      longhorn_disks = {}
      talos_version_override = null
    }
    worker-4 = {
      proxmox_node = "pve05"
      ip           = "192.168.1.71"
      vm_id        = 110
      mac_address  = "BC:24:11:00:00:65"
      cores        = 10
      memory       = 18432
      os_disk_size = 950
      node_class   = "performance"
      kubelet_args = { "max-pods" = "250" }
      sysctls = {
        "net.netfilter.nf_conntrack_max" = "1048576"
        "net.core.netdev_max_backlog"    = "5000"
      }
      longhorn_disks = {}
      talos_version_override = null
    }
    worker-5 = {
      proxmox_node = "pve06"
      ip           = "192.168.1.72"
      vm_id        = 111
      mac_address  = "BC:24:11:00:00:72"
      cores        = 6
      memory       = 12288
      os_disk_size = 32
      node_class   = "standard"
      kubelet_args = {}
      sysctls      = {}
      longhorn_disks = {
        scsi1 = { datastore = "local-lvm",    size = 260, device = "/dev/sdb" }
        scsi2 = { datastore = "longhorn-lvm", size = 110, device = "/dev/sdc" }
        scsi3 = { datastore = "longhorn-lvm", size = 110, device = "/dev/sdd" }
        scsi4 = { datastore = "longhorn-lvm", size = 110, device = "/dev/sde" }
      }
      # v1.13.3+ fixes the iscsi-tools path regression. Use the latest
      # v1.13.x patch that also includes the open-iscsi 2.1.12 fix.
      talos_version_override = "v1.13.9"
    }
  }

  # Resolve the effective Talos version per worker.
  worker_talos_version = {
    for name, w in local.workers :
    name => w.talos_version_override != null ? w.talos_version_override : local.talos_version
  }

  worker_labels = {
    for name, w in local.workers : name => compact([
      (w.node_class != "standard" || length(w.longhorn_disks) > 0) ? "node-class=${w.node_class}" : "",
      length(w.longhorn_disks) > 0 ? "storage.capability=local-block" : "",
      length(w.longhorn_disks) > 0 ? "node.longhorn.io/create-default-disk=config" : "",
    ])
  }

  worker_ips = [for k in sort(keys(local.workers)) : local.workers[k].ip]
  all_ips    = concat([local.control_plane_ip], local.worker_ips)

  cluster_endpoint = "https://${local.control_plane_ip}:6443"
}