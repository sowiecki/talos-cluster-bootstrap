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
    # file_id      = "local:iso/talos-v1.13.0-nocloud-amd64.raw.img"
    file_id      = "local:iso/talos-v1.13.11-nocloud-amd64.raw.img"
  }

  dynamic "disk" {
    for_each = each.value.longhorn_disks
    content {
      datastore_id = disk.value.datastore
      interface    = disk.key
      size         = disk.value.size
      file_format  = "raw"
    }
  }

  network_device {
    bridge      = local.bridge
    model       = "virtio"
    mac_address = each.value.mac_address
  }

  agent {
    enabled = false
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
    ignore_changes = [disk, initialization]
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
      yamlencode({
        machine = merge(
          {
            install = merge(
              { disk = "/dev/sda" },
              length(each.value.longhorn_disks) > 0 ? {
                image = "factory.talos.dev/installer/${talos_image_factory_schematic.worker5.id}:${local.worker_talos_version[each.key]}"
              } : {}
            )

            time = { servers = ["pool.ntp.org"] }

            kubelet = {
              extraArgs = merge(
                { node-ip = each.value.ip },
                length(local.worker_labels[each.key]) > 0 ? {
                  "node-labels" = join(",", local.worker_labels[each.key])
                } : {},
                each.value.kubelet_args,
              )
            }

            sysctls = merge(
              {
                "vm.max_map_count"   = "262144"
                "net.core.somaxconn" = "4096"
              },
              each.value.sysctls,
            )
          },

          length(each.value.longhorn_disks) > 0 ? {
            nodeAnnotations = {
              "node.longhorn.io/default-disks-config" = jsonencode([
                for slot, spec in each.value.longhorn_disks : {
                  path            = "/var/mnt/longhorn-${slot}"
                  allowScheduling = true
                }
              ])
            }
          } : {}
        )

        cluster = {
          network = { cni = { name = "none" } }
        }
      }),

      yamlencode({
        machine = {
          network = { nameservers = local.dns_servers }
        }
      }),
    ],

    length(each.value.longhorn_disks) > 0 ? [
      yamlencode({
        machine = {
          disks = [
            for slot, spec in each.value.longhorn_disks : {
              device     = spec.device
              partitions = [{ mountpoint = "/var/mnt/longhorn-${slot}", size = 0 }]
            }
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