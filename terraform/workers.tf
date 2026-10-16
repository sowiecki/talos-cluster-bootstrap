# ----------------------------------------------------------------------
# Talos installer schematics
# ----------------------------------------------------------------------
resource "talos_image_factory_schematic" "worker5" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent",
          "siderolabs/iscsi-tools",
          "siderolabs/util-linux-tools",
        ]
      }
      extraKernelArgs = ["console=tty0", "console=ttyS0"]
    }
  })
}

# ----------------------------------------------------------------------
# Worker VMs - Explicit declarations
# ----------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "worker_1" {
  name      = "${local.cluster_name}-worker-1"
  node_name = "pve02"
  tags      = ["talos", "worker"]
  started   = true
  vm_id     = 106

  cpu {
    cores = 10
    type  = "host"
  }

  memory {
    dedicated = 14000
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 950
    file_format  = "raw"
    file_id      = "local:iso/talos-v1.13.0-nocloud-amd64.raw.img"
  }

  network_device {
    bridge      = local.bridge
    model       = "virtio"
    mac_address = "BC:24:11:00:00:62"
  }

  agent {
    enabled = true
    timeout = "15s"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.62/24"
        gateway = local.gateway
      }
    }
    dns {
      servers = local.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [disk, initialization, agent]
  }
}

resource "proxmox_virtual_environment_vm" "worker_2" {
  name      = "${local.cluster_name}-worker-2"
  node_name = "pve03"
  tags      = ["talos", "worker"]
  started   = true
  vm_id     = 107

  cpu {
    cores = 10
    type  = "host"
  }

  memory {
    dedicated = 14000
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 950
    file_format  = "raw"
    file_id      = "local:iso/talos-v1.13.0-nocloud-amd64.raw.img"
  }

  network_device {
    bridge      = local.bridge
    model       = "virtio"
    mac_address = "BC:24:11:00:00:63"
  }

  agent {
    enabled = true
    timeout = "15s"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.63/24"
        gateway = local.gateway
      }
    }
    dns {
      servers = local.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [disk, initialization, agent]
  }
}

resource "proxmox_virtual_environment_vm" "worker_3" {
  name      = "${local.cluster_name}-worker-3"
  node_name = "pve04"
  tags      = ["talos", "worker"]
  started   = true
  vm_id     = 108

  cpu {
    cores = 6
    type  = "host"
  }

  memory {
    dedicated = 14000
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 950
    file_format  = "raw"
    file_id      = "local:iso/talos-v1.13.0-nocloud-amd64.raw.img"
  }

  network_device {
    bridge      = local.bridge
    model       = "virtio"
    mac_address = "BC:24:11:00:00:64"
  }

  agent {
    enabled = true
    timeout = "15s"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.64/24"
        gateway = local.gateway
      }
    }
    dns {
      servers = local.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [disk, initialization, agent]
  }
}

resource "proxmox_virtual_environment_vm" "worker_4" {
  name      = "${local.cluster_name}-worker-4"
  node_name = "pve05"
  tags      = ["talos", "worker"]
  started   = true
  vm_id     = 110

  cpu {
    cores = 10
    type  = "host"
  }

  memory {
    dedicated = 18432
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 950
    file_format  = "raw"
    file_id      = "local:iso/talos-v1.13.0-nocloud-amd64.raw.img"
  }

  network_device {
    bridge      = local.bridge
    model       = "virtio"
    mac_address = "BC:24:11:00:00:65"
  }

  agent {
    enabled = true
    timeout = "15s"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.71/24"
        gateway = local.gateway
      }
    }
    dns {
      servers = local.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [disk, initialization, agent]
  }
}

resource "proxmox_virtual_environment_vm" "worker_5" {
  name      = "${local.cluster_name}-worker-5"
  node_name = "pve06"
  tags      = ["talos", "worker", "storage-local-block"]
  started   = true
  vm_id     = 111

  cpu {
    cores = 6
    type  = "host"
  }

  memory {
    dedicated = 12288
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    file_format  = "raw"
    file_id      = "local:iso/talos-v1.13.11-nocloud-amd64.raw.img"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi1"
    size         = 260
    file_format  = "raw"
  }

  disk {
    datastore_id = "longhorn-lvm"
    interface    = "scsi2"
    size         = 110
    file_format  = "raw"
  }

  disk {
    datastore_id = "longhorn-lvm"
    interface    = "scsi3"
    size         = 110
    file_format  = "raw"
  }

  disk {
    datastore_id = "longhorn-lvm"
    interface    = "scsi4"
    size         = 110
    file_format  = "raw"
  }

  network_device {
    bridge      = local.bridge
    model       = "virtio"
    mac_address = "BC:24:11:00:00:72"
  }

  agent {
    enabled = true
    timeout = "15s"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.75/24"
        gateway = local.gateway
      }
    }
    dns {
      servers = local.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [initialization, agent]
  }
}

# ----------------------------------------------------------------------
# Talos machine configurations - Explicit declarations
# ----------------------------------------------------------------------

data "talos_machine_configuration" "worker_1" {
  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v1.13.0"
  kubernetes_version = "1.35.0"

  config_patches = [
    yamlencode({
      machine = {
        install = { disk = "/dev/sda" }
        time    = { servers = ["pool.ntp.org"] }
        network = {
          nameservers = local.dns_servers
          interfaces = [{
            interface = "eth0"
            addresses = ["192.168.1.62/24"]
            routes    = [{ network = "0.0.0.0/0", gateway = local.gateway }]
          }]
        }
        kubelet = {
          extraArgs = { node-ip = "192.168.1.62" }
        }
      }
      cluster = { network = { cni = { name = "none" } } }
    })
  ]
}

data "talos_machine_configuration" "worker_2" {
  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v1.13.0"
  kubernetes_version = "1.35.0"

  config_patches = [
    yamlencode({
      machine = {
        install = { disk = "/dev/sda" }
        time    = { servers = ["pool.ntp.org"] }
        network = {
          nameservers = local.dns_servers
          interfaces = [{
            interface = "eth0"
            addresses = ["192.168.1.63/24"]
            routes    = [{ network = "0.0.0.0/0", gateway = local.gateway }]
          }]
        }
        kubelet = {
          extraArgs = { node-ip = "192.168.1.63" }
        }
      }
      cluster = { network = { cni = { name = "none" } } }
    })
  ]
}

data "talos_machine_configuration" "worker_3" {
  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v1.13.0"
  kubernetes_version = "1.35.0"

  config_patches = [
    yamlencode({
      machine = {
        install = { disk = "/dev/sda" }
        time    = { servers = ["pool.ntp.org"] }
        network = {
          nameservers = local.dns_servers
          interfaces = [{
            interface = "eth0"
            addresses = ["192.168.1.64/24"]
            routes    = [{ network = "0.0.0.0/0", gateway = local.gateway }]
          }]
        }
        kubelet = {
          extraArgs = { node-ip = "192.168.1.64" }
        }
      }
      cluster = { network = { cni = { name = "none" } } }
    })
  ]
}

data "talos_machine_configuration" "worker_4" {
  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v1.13.0"
  kubernetes_version = "1.35.0"

  config_patches = [
    yamlencode({
      machine = {
        install = { disk = "/dev/sda" }
        time    = { servers = ["pool.ntp.org"] }
        network = {
          nameservers = local.dns_servers
          interfaces = [{
            interface = "eth0"
            addresses = ["192.168.1.71/24"]
            routes    = [{ network = "0.0.0.0/0", gateway = local.gateway }]
          }]
        }
        kubelet = {
          extraArgs = {
            node-ip       = "192.168.1.71"
            "max-pods"    = "250"
            "node-labels" = "node-class=performance"
          }
        }
        sysctls = {
          "net.netfilter.nf_conntrack_max" = "1048576"
          "net.core.netdev_max_backlog"    = "5000"
        }
      }
      cluster = { network = { cni = { name = "none" } } }
    })
  ]
}

data "talos_machine_configuration" "worker_5" {
  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v1.13.11"
  kubernetes_version = "1.35.0"

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          image = "factory.talos.dev/installer/${talos_image_factory_schematic.worker5.id}:v1.13.11"
        }
        time = { servers = ["pool.ntp.org"] }
        network = {
          nameservers = local.dns_servers
          interfaces = [{
            interface = "eth0"
            addresses = ["192.168.1.75/24"]
            routes    = [{ network = "0.0.0.0/0", gateway = local.gateway }]
          }]
        }
        kubelet = {
          extraArgs = {
            node-ip       = "192.168.1.75"
            "node-labels" = "storage.capability=local-block,node.longhorn.io/create-default-disk=config"
          }
        }
        disks = [
          { device = "/dev/sdb", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi1", size = 0 }] },
          { device = "/dev/sdc", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi2", size = 0 }] },
          { device = "/dev/sdd", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi3", size = 0 }] },
          { device = "/dev/sde", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi4", size = 0 }] }
        ]
      }
      cluster = { network = { cni = { name = "none" } } }
    })
  ]
}

# ----------------------------------------------------------------------
# Apply configurations to each worker
# ----------------------------------------------------------------------

resource "talos_machine_configuration_apply" "worker_1" {
  node                        = "192.168.1.62"
  machine_configuration_input = data.talos_machine_configuration.worker_1.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

resource "talos_machine_configuration_apply" "worker_2" {
  node                        = "192.168.1.63"
  machine_configuration_input = data.talos_machine_configuration.worker_2.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

resource "talos_machine_configuration_apply" "worker_3" {
  node                        = "192.168.1.64"
  machine_configuration_input = data.talos_machine_configuration.worker_3.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

resource "talos_machine_configuration_apply" "worker_4" {
  node                        = "192.168.1.71"
  machine_configuration_input = data.talos_machine_configuration.worker_4.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

resource "talos_machine_configuration_apply" "worker_5" {
  node                        = "192.168.1.75"
  machine_configuration_input = data.talos_machine_configuration.worker_5.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

# ----------------------------------------------------------------------
# Longhorn labels and Node CRD - Explicit declarations
# ----------------------------------------------------------------------

resource "kubernetes_labels" "worker_5_longhorn" {
  force       = true
  api_version = "v1"
  kind        = "Node"

  metadata {
    name = "${local.cluster_name}-worker-5"
  }

  labels = {
    "storage.capability"                   = "local-block"
    "node.longhorn.io/create-default-disk" = "config"
  }
}

resource "kubernetes_manifest" "worker_5_longhorn_node" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Node"
    metadata = {
      name      = "${local.cluster_name}-worker-5"
      namespace = "longhorn-system"
    }
    spec = {
      allowScheduling   = true
      evictionRequested = false
      tags              = []
      disks = {
        "longhorn-scsi1" = {
          path            = "/var/mnt/longhorn-scsi1"
          allowScheduling = true
          storageReserved = 0
          tags            = []
        }
        "longhorn-scsi2" = {
          path            = "/var/mnt/longhorn-scsi2"
          allowScheduling = true
          storageReserved = 0
          tags            = []
        }
        "longhorn-scsi3" = {
          path            = "/var/mnt/longhorn-scsi3"
          allowScheduling = true
          storageReserved = 0
          tags            = []
        }
        "longhorn-scsi4" = {
          path            = "/var/mnt/longhorn-scsi4"
          allowScheduling = true
          storageReserved = 0
          tags            = []
        }
      }
    }
  }

  depends_on = [
    talos_machine_configuration_apply.worker_5,
    kubernetes_labels.worker_5_longhorn,
    helm_release.longhorn
  ]
}
