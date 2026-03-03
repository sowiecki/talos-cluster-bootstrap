# ----------------------------------------------------------------------
# 1. Create a custom Talos image with qemu-guest-agent
# ----------------------------------------------------------------------
resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/schematic.yaml")
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  node_name               = local.node_name
  datastore_id            = local.datastore_id
  content_type            = "iso"
  file_name               = "talos-${talos_image_factory_schematic.this.id}-v1.9.5-nocloud-amd64.raw.img"
  url                     = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/v1.9.5/nocloud-amd64.raw.zst"
  decompression_algorithm = "zst"
  overwrite               = false
}

# ----------------------------------------------------------------------
# 2. Create a template VM directly from the downloaded image
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "talos_template" {
  name      = "talos-template"
  node_name = local.node_name
  vm_id     = 9999
  template  = true # Creates a template directly
  started   = false

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "scsi0"
    size         = 10
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.talos_image.id
  }

  network_device {
    bridge = local.bridge
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }
}

# ----------------------------------------------------------------------
# 3. Generate Talos secrets (version locked)
# ----------------------------------------------------------------------
resource "talos_machine_secrets" "this" {
  talos_version = local.talos_version
}

# ----------------------------------------------------------------------
# 4. Create the cluster VMs (clone from the template)
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "control_plane" {
  depends_on = [proxmox_virtual_environment_vm.talos_template]

  name      = "${local.cluster_name}-cp-1"
  node_name = local.node_name
  tags      = ["talos", "control-plane"]

  clone {
    vm_id = proxmox_virtual_environment_vm.talos_template.vm_id
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
  }

  network_device {
    bridge = local.bridge
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${local.control_plane_ip}/24"
        gateway = local.gateway
      }
    }
    dns {
      servers = local.dns_servers
    }
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  count      = 2
  depends_on = [proxmox_virtual_environment_vm.talos_template]

  name      = "${local.cluster_name}-worker-${count.index + 1}"
  node_name = local.node_name
  tags      = ["talos", "worker"]

  clone {
    vm_id = proxmox_virtual_environment_vm.talos_template.vm_id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
  }

  network_device {
    bridge = local.bridge
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${local.worker_ips[count.index]}/24"
        gateway = local.gateway
      }
    }
    dns {
      servers = local.dns_servers
    }
  }
}

# ----------------------------------------------------------------------
# 5. Wait for VMs to boot
# ----------------------------------------------------------------------
resource "time_sleep" "wait_for_vms" {
  depends_on = [
    proxmox_virtual_environment_vm.control_plane,
    proxmox_virtual_environment_vm.worker
  ]
  create_duration = "60s"
}

# ----------------------------------------------------------------------
# 6. Prepare Talos machine configurations
# ----------------------------------------------------------------------
data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
      }
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
      }
    })
  ]
}

data "talos_machine_configuration" "worker" {
  count            = 2
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
      }
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
      }
    })
  ]
}

# ----------------------------------------------------------------------
# 7. Apply configurations to nodes
# ----------------------------------------------------------------------
resource "talos_machine_configuration_apply" "controlplane" {
  node                        = local.control_plane_ip
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [time_sleep.wait_for_vms]
}

resource "talos_machine_configuration_apply" "worker" {
  count                       = 2
  node                        = local.worker_ips[count.index]
  machine_configuration_input = data.talos_machine_configuration.worker[count.index].machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

# ----------------------------------------------------------------------
# 8. Bootstrap the cluster
# ----------------------------------------------------------------------
resource "talos_machine_bootstrap" "controlplane" {
  node                 = local.control_plane_ip
  client_configuration = talos_machine_secrets.this.client_configuration
  depends_on           = [talos_machine_configuration_apply.controlplane]
}

# ----------------------------------------------------------------------
# 9. Wait for bootstrap to complete
# ----------------------------------------------------------------------
resource "time_sleep" "wait_for_bootstrap" {
  depends_on      = [talos_machine_bootstrap.controlplane]
  create_duration = "180s"
}

# ----------------------------------------------------------------------
# 10. Generate talosconfig and kubeconfig
# ----------------------------------------------------------------------
data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.control_plane_ip]
  nodes                = local.all_ips
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talosconfig"
}

# Fetch kubeconfig with retries
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [time_sleep.wait_for_bootstrap, local_file.talosconfig]

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      COUNTER=0
      MAX_RETRIES=60
      SLEEP_SEC=10
      NODE="${local.control_plane_ip}"
      until talosctl --talosconfig talosconfig -n $NODE kubeconfig .; do
        if [ $COUNTER -ge $MAX_RETRIES ]; then
          echo "Failed to get kubeconfig after $((MAX_RETRIES * SLEEP_SEC)) seconds"
          exit 1
        fi
        echo "Waiting for Kubernetes API to be ready... ($COUNTER/$MAX_RETRIES) - connecting to node $NODE"
        sleep $SLEEP_SEC
        COUNTER=$((COUNTER+1))
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

# ----------------------------------------------------------------------
# 11. Outputs
# ----------------------------------------------------------------------
output "kubeconfig_path" {
  value = abspath("${path.module}/kubeconfig")
}

output "talosconfig_path" {
  value = abspath("${path.module}/talosconfig")
}

output "control_plane_ip" {
  value = local.control_plane_ip
}

output "worker_ips" {
  value = local.worker_ips
}
