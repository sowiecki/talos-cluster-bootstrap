# ----------------------------------------------------------------------
# Talos installer schematic for storage-capable workers
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
# Worker VMs
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "worker" {
  for_each = local.workers

  depends_on = [
    talos_image_factory_schematic.this,
    talos_image_factory_schematic.worker5,
  ]

  name      = "${local.cluster_name}-${each.key}"
  node_name = each.value.proxmox_node
  tags = length(each.value.longhorn_disks) > 0 ? [
    "talos", "worker", "storage-local-block",
    ] : [
    "talos", "worker",
  ]
  started = true
  vm_id   = each.value.vm_id

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.os_disk_size
    file_format  = "raw"
    file_id      = "local:iso/talos-v1.13.11-nocloud-amd64.raw.img"
  }

  dynamic "disk" {
    for_each = each.value.longhorn_disks
    content {
      datastore_id = disk.value.datastore
      interface    = disk.key
      size         = disk.value.size
      file_format  = "raw"
      serial       = "longhorn-${disk.key}"
    }
  }

  network_device {
    bridge      = local.bridge
    model       = "virtio"
    mac_address = each.value.mac_address
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
        address = "${each.value.ip}/24"
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

# ----------------------------------------------------------------------
# Talos machine configuration per worker
# ----------------------------------------------------------------------
data "talos_machine_configuration" "worker" {
  for_each = local.workers

  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = local.worker_talos_version[each.key]
  kubernetes_version = "1.35.0"

  config_patches = concat(
    [
      # Base worker configuration
      yamlencode({
        machine = {
          install = { disk = "/dev/sda" }
          time    = { servers = ["pool.ntp.org"] }
          network = {
            nameservers = local.dns_servers
            interfaces = [{
              interface = "eth0"
              addresses = ["${each.value.ip}/24"]
              routes    = [{ network = "0.0.0.0/0", gateway = local.gateway }]
            }]
          }
          kubelet = {
            extraArgs = merge(
              { node-ip = each.value.ip },
              length(local.worker_labels[each.key]) > 0 ? {
                "node-labels" = join(",", local.worker_labels[each.key])
              } : {},
              each.value.kubelet_args,
            )
          }
        }
        cluster = { network = { cni = { name = "none" } } }
      }),
    ],
    # Explicit, readable Longhorn disk declarations for worker-5
    # No dynamic loops, no complex calculations. Just clear, explicit intent.
    # (Note: .machine.disks shows a deprecation warning in 1.13, but remains
    # fully functional and is the most readable way to explicitly declare mounts).
    each.key == "worker-5" ? [
      yamlencode({
        machine = {
          disks = [
            { device = "/dev/sdb", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi1", size = 0 }] },
            { device = "/dev/sdc", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi2", size = 0 }] },
            { device = "/dev/sdd", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi3", size = 0 }] },
            { device = "/dev/sde", partitions = [{ mountpoint = "/var/mnt/longhorn-scsi4", size = 0 }] }
          ]
        }
      })
    ] : []
  )
}

# ----------------------------------------------------------------------
# Apply config to each worker
# ----------------------------------------------------------------------
resource "talos_machine_configuration_apply" "worker" {
  for_each = local.workers

  node                        = each.value.ip
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration

  depends_on = [talos_machine_configuration_apply.controlplane]
}

# ----------------------------------------------------------------------
# Ensure Longhorn-required labels are present on nodes with storage.
#
# workers.tf intends to set these via kubelet extraArgs.node-labels, but
# that block is not reliably rendered into the machine configuration by
# the Talos provider. This resource enforces the same labels at the
# Kubernetes level. Both mechanisms can coexist: kubelet applies them on
# join, this resource ensures they persist.
# ----------------------------------------------------------------------
resource "kubernetes_labels" "worker_longhorn" {
  for_each = {
    for name, w in local.workers : name => w
    if length(w.longhorn_disks) > 0
  }

  api_version = "v1"
  kind        = "Node"

  metadata {
    name = "${local.cluster_name}-${each.key}"
  }

  labels = {
    "storage.capability"                   = "local-block"
    "node.longhorn.io/create-default-disk" = "config"
  }
}
