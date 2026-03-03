# ----------------------------------------------------------------------
# 1. Create a custom Talos image with qemu-guest-agent
# ----------------------------------------------------------------------
resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/schematic.yaml")
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  node_name               = "pve01"
  datastore_id            = "k3s-storage"
  content_type            = "iso"
  file_name               = "talos-${talos_image_factory_schematic.this.id}-v1.9.5-nocloud-amd64.raw.xz.img"
  url                     = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/v1.9.5/nocloud-amd64.raw.xz"
  decompression_algorithm = "zst"
  overwrite               = false
}

# ----------------------------------------------------------------------
# 2. Create a template VM from the downloaded image (stopped)
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "talos_template_vm" {
  name      = "talos-template-auto"
  node_name = "pve01"
  vm_id     = 9999
  started   = false # <-- Keep stopped for template conversion

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "k3s-storage"
    interface    = "scsi0"
    size         = 10
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.talos_image.id
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }
}

# Convert the VM to a template
resource "null_resource" "convert_to_template" {
  depends_on = [proxmox_virtual_environment_vm.talos_template_vm]

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/proxmox-k3s root@192.168.1.65 qm template ${proxmox_virtual_environment_vm.talos_template_vm.vm_id}"
  }
}

# ----------------------------------------------------------------------
# 3. Generate Talos secrets (explicitly set version to match nodes)
# ----------------------------------------------------------------------
resource "talos_machine_secrets" "this" {
  talos_version = "v1.9.5"
}

# ----------------------------------------------------------------------
# 4. Create the cluster VMs (clone from the template)
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "control_plane" {
  depends_on = [null_resource.convert_to_template]

  name      = "nase-dev-prod-cp-1"
  node_name = "pve01"
  tags      = ["talos", "control-plane"]

  clone {
    vm_id = proxmox_virtual_environment_vm.talos_template_vm.vm_id
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "k3s-storage"
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.61/24"
        gateway = "192.168.1.1"
      }
    }
    dns {
      servers = ["192.168.1.100", "8.8.8.8"]
    }
  }
}

resource "proxmox_virtual_environment_vm" "worker_1" {
  depends_on = [null_resource.convert_to_template]

  name      = "nase-dev-prod-worker-1"
  node_name = "pve01"
  tags      = ["talos", "worker"]

  clone {
    vm_id = proxmox_virtual_environment_vm.talos_template_vm.vm_id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "k3s-storage"
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.62/24"
        gateway = "192.168.1.1"
      }
    }
    dns {
      servers = ["192.168.1.100", "8.8.8.8"]
    }
  }
}

resource "proxmox_virtual_environment_vm" "worker_2" {
  depends_on = [null_resource.convert_to_template]

  name      = "nase-dev-prod-worker-2"
  node_name = "pve01"
  tags      = ["talos", "worker"]

  clone {
    vm_id = proxmox_virtual_environment_vm.talos_template_vm.vm_id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "k3s-storage"
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.63/24"
        gateway = "192.168.1.1"
      }
    }
    dns {
      servers = ["192.168.1.100", "8.8.8.8"]
    }
  }
}

# ----------------------------------------------------------------------
# 5. Wait for VMs to boot
# ----------------------------------------------------------------------
resource "time_sleep" "wait_for_vms" {
  depends_on = [
    proxmox_virtual_environment_vm.control_plane,
    proxmox_virtual_environment_vm.worker_1,
    proxmox_virtual_environment_vm.worker_2
  ]
  create_duration = "60s"
}

# ----------------------------------------------------------------------
# 6. Prepare Talos machine configurations (version locked to v1.9.5)
# ----------------------------------------------------------------------
data "talos_machine_configuration" "controlplane" {
  cluster_name     = "nase-dev-prod"
  cluster_endpoint = "https://192.168.1.61:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = "v1.9.5"

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
  cluster_name     = "nase-dev-prod"
  cluster_endpoint = "https://192.168.1.61:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = "v1.9.5"

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

# Generate a proper talosconfig file with endpoints
data "talos_client_configuration" "this" {
  cluster_name         = "nase-dev-prod"
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = ["192.168.1.61"]                                 # Control plane API endpoint
  nodes                = ["192.168.1.61", "192.168.1.62", "192.168.1.63"] # All nodes
}

# ----------------------------------------------------------------------
# 7. Apply configurations to nodes
# ----------------------------------------------------------------------
resource "talos_machine_configuration_apply" "controlplane" {
  node                        = "192.168.1.61"
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [time_sleep.wait_for_vms]
}

resource "talos_machine_configuration_apply" "worker" {
  count                       = 2
  node                        = count.index == 0 ? "192.168.1.62" : "192.168.1.63"
  machine_configuration_input = data.talos_machine_configuration.worker[count.index].machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

# ----------------------------------------------------------------------
# 8. Wait for bootstrap to complete
# ----------------------------------------------------------------------
resource "time_sleep" "wait_for_bootstrap" {
  depends_on      = [talos_machine_configuration_apply.worker]
  create_duration = "180s"
}

# ----------------------------------------------------------------------
# 9. Write talosconfig (needed for talosctl)
# ----------------------------------------------------------------------
resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talosconfig"
}

# ----------------------------------------------------------------------
# 10. Retrieve kubeconfig with retries (using -n for node)
# ----------------------------------------------------------------------
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [time_sleep.wait_for_bootstrap, local_file.talosconfig]

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      COUNTER=0
      MAX_RETRIES=60
      SLEEP_SEC=10
      NODE="192.168.1.61"
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
# 11. Output the path to kubeconfig
# ----------------------------------------------------------------------
output "kubeconfig_path" {
  value = abspath("${path.module}/kubeconfig")
}
