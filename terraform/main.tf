# ----------------------------------------------------------------------
# 1. Create a custom Talos image with qemu-guest-agent
# ----------------------------------------------------------------------
resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/schematic.yaml")
}

# ----------------------------------------------------------------------
# 2. Generate Talos secrets
# ----------------------------------------------------------------------
resource "talos_machine_secrets" "this" {
  talos_version = local.talos_version
}

# ----------------------------------------------------------------------
# 3. Create VMs – ISO referenced directly by path (no download resource)
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "control_plane" {
  name      = "${local.cluster_name}-cp-1"
  node_name = "pve01"
  tags      = ["talos", "control-plane"]
  started   = true
  vm_id     = 105

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
    file_id      = "local:iso/talos-${talos_image_factory_schematic.this.id}-v1.9.5-nocloud-amd64.raw.img"
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
  count = length(local.worker_ips)

  node_name = element(local.proxmox_nodes, count.index + 1)
  name      = "${local.cluster_name}-worker-${count.index + 1}"
  tags      = ["talos", "worker"]
  started   = true
  vm_id     = 106 + count.index

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
    file_id      = "local:iso/talos-${talos_image_factory_schematic.this.id}-v1.9.5-nocloud-amd64.raw.img"
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
# 4. Wait for VMs to boot
# ----------------------------------------------------------------------
resource "time_sleep" "wait_for_vms" {
  depends_on = [
    proxmox_virtual_environment_vm.control_plane,
    proxmox_virtual_environment_vm.worker
  ]
  create_duration = "60s"
}

# ----------------------------------------------------------------------
# 5. Prepare Talos machine configurations (CNI = "none")
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
        certSANs = [local.control_plane_ip]
        time = {
          servers = ["pool.ntp.org"]
        }
        kubelet = {
          extraArgs = {
            node-ip = local.control_plane_ip
          }
        }
        sysctls = {
          "vm.max_map_count"   = "262144"
          "net.core.somaxconn" = "4096"
        }
      }
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        apiServer = {
          certSANs = [local.control_plane_ip]
        }
      }
    })
  ]
}

data "talos_machine_configuration" "worker" {
  count            = length(local.worker_ips)
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
        time = {
          servers = ["pool.ntp.org"]
        }
        kubelet = {
          extraArgs = {
            node-ip = local.worker_ips[count.index]
          }
        }
        sysctls = {
          "vm.max_map_count"   = "262144"
          "net.core.somaxconn" = "4096"
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
# 6. Apply configurations to nodes
# ----------------------------------------------------------------------
resource "talos_machine_configuration_apply" "controlplane" {
  node                        = local.control_plane_ip
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [time_sleep.wait_for_vms]
}

resource "talos_machine_configuration_apply" "worker" {
  count                       = length(local.worker_ips)
  node                        = local.worker_ips[count.index]
  machine_configuration_input = data.talos_machine_configuration.worker[count.index].machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  depends_on                  = [talos_machine_configuration_apply.controlplane]
}

# ----------------------------------------------------------------------
# 7. Bootstrap the cluster
# ----------------------------------------------------------------------
resource "talos_machine_bootstrap" "controlplane" {
  node                 = local.control_plane_ip
  client_configuration = talos_machine_secrets.this.client_configuration
  depends_on           = [talos_machine_configuration_apply.controlplane]
}

# ----------------------------------------------------------------------
# 8. Wait for bootstrap to complete (10 minutes)
# ----------------------------------------------------------------------
resource "time_sleep" "wait_for_bootstrap" {
  depends_on      = [talos_machine_bootstrap.controlplane]
  create_duration = "600s"
}

# ----------------------------------------------------------------------
# 9. Generate talosconfig
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

# ----------------------------------------------------------------------
# 10. Fetch kubeconfig (with correct talosctl syntax)
# ----------------------------------------------------------------------
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [time_sleep.wait_for_bootstrap, local_file.talosconfig]
  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      COUNTER=0
      MAX_RETRIES=60
      SLEEP_SEC=10
      NODE="${local.control_plane_ip}"
      until talosctl --talosconfig talosconfig --nodes $NODE kubeconfig .; do
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
  triggers = { always_run = timestamp() }
}

# ----------------------------------------------------------------------
# 11. Extract Kubernetes CA from kubeconfig for the provider
# ----------------------------------------------------------------------
data "local_file" "kubeconfig" {
  depends_on = [null_resource.fetch_kubeconfig]
  filename   = local.kubeconfig_path
}

locals {
  kubeconfig_yaml = yamldecode(data.local_file.kubeconfig.content)
  cluster_ca_cert = base64decode(local.kubeconfig_yaml.clusters[0].cluster.certificate-authority-data)
  k8s_host        = local.kubeconfig_yaml.clusters[0].cluster.server
  k8s_client_cert = base64decode(local.kubeconfig_yaml.users[0].user.client-certificate-data)
  k8s_client_key  = base64decode(local.kubeconfig_yaml.users[0].user.client-key-data)
}

# ----------------------------------------------------------------------
# 12. Outputs
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

# ----------------------------------------------------------------------
# 13. Install Cilium
# ----------------------------------------------------------------------
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"
  version    = "1.19.1"
  timeout    = 900

  values = [
    yamlencode({
      kubeProxyReplacement = "true"
      routingMode          = "tunnel"
      tunnelProtocol       = "geneve"
      ipv4                 = { enabled = true }
      ipv6                 = { enabled = false }
      hubble = {
        enabled = true
        relay   = { enabled = true }
        ui      = { enabled = true }
      }
      securityContext = {
        privileged   = true
        capabilities = { drop = [] }
      }
      initSecurityContext = {
        privileged   = true
        capabilities = { drop = [] }
      }
      cni = { uninstall = false }
    })
  ]

  depends_on = [null_resource.fetch_kubeconfig]
}

# ----------------------------------------------------------------------
# 14. Wait for nodes to become Ready after Cilium
# ----------------------------------------------------------------------
resource "time_sleep" "wait_for_nodes_ready" {
  depends_on      = [helm_release.cilium]
  create_duration = "180s"
}

# ----------------------------------------------------------------------
# 15. NFS CSI Driver (for TrueNAS persistent volumes)
# ----------------------------------------------------------------------
resource "helm_release" "nfs_csi" {
  name       = "nfs-csi"
  repository = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart      = "nfs-subdir-external-provisioner"
  namespace  = "kube-system"
  version    = "4.0.18"

  values = [
    yamlencode({
      nfs = {
        server = local.truenas_nfs_server
        path   = "/mnt/Uldaman/k8s/nfs/v"
      }
      storageClass = {
        name                 = "truenas-nfs"
        defaultClass         = true
        reclaimPolicy        = "Delete"
        allowVolumeExpansion = true
        mountOptions         = ["nfsvers=4", "hard", "noatime"]
      }
      replicaCount = 1
    })
  ]

  depends_on = [helm_release.cilium]
}

# ----------------------------------------------------------------------
# 16. API Readiness Check (ensures cluster is fully responsive)
# ----------------------------------------------------------------------
resource "null_resource" "wait_for_api" {
  depends_on = [helm_release.cilium, time_sleep.wait_for_nodes_ready]

  provisioner "local-exec" {
    command     = <<-EOT
      echo "Waiting for Kubernetes API to be fully reachable..."
      for i in {1..30}; do
        if kubectl --request-timeout=5s get nodes &>/dev/null; then
          echo "API is reachable."
          exit 0
        fi
        echo "Attempt $i: API not reachable, waiting 10s..."
        sleep 10
      done
      echo "API failed to become reachable after 5 minutes."
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# ----------------------------------------------------------------------
# 17. MetalLB Installation
# ----------------------------------------------------------------------
resource "terraform_data" "metallb_manifests" {
  depends_on = [null_resource.wait_for_api]

  triggers_replace = "v0.14.9"

  provisioner "local-exec" {
    command     = <<-EOT
      echo "Applying MetalLB manifests..."
      kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when        = destroy
    command     = <<-EOT
      echo "Removing MetalLB manifests..."
      kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml || true
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "terraform_data" "wait_for_crds" {
  depends_on = [terraform_data.metallb_manifests]

  provisioner "local-exec" {
    command     = <<-EOT
      echo "Waiting for MetalLB CRDs..."
      until kubectl get crd ipaddresspools.metallb.io &>/dev/null; do
        sleep 5
      done
      kubectl wait --for=condition=established --timeout=60s crd/ipaddresspools.metallb.io
      echo "CRDs ready."
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "terraform_data" "metallb_config_content" {
  depends_on = [terraform_data.wait_for_crds]

  input = {
    ip_range = "192.168.1.21-192.168.1.30"
  }

  provisioner "local-exec" {
    when        = destroy
    command     = <<-EOT
      if [ -n "${self.input["ip_range"]}" ]; then
        kubectl delete ipaddresspool -n metallb-system homelab-pool || true
        kubectl delete l2advertisement -n metallb-system homelab || true
      fi
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "terraform_data" "apply_metallb_config" {
  depends_on = [terraform_data.metallb_config_content]

  triggers_replace = jsonencode(terraform_data.metallb_config_content.input)

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      for i in {1..5}; do
        echo "Attempt $i to apply MetalLB config..."
        if kubectl apply -f - <<'APPLY_EOF' 2>/dev/null; then
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
  - ${terraform_data.metallb_config_content.input["ip_range"]}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab
  namespace: metallb-system
spec:
  ipAddressPools:
  - homelab-pool
APPLY_EOF
          echo "MetalLB config applied successfully."
          exit 0
        else
          echo "Attempt $i failed, waiting 10s..."
          sleep 10
        fi
      done
      echo "All attempts failed. Exiting."
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# ----------------------------------------------------------------------
# 18. Brief wait after MetalLB to allow webhooks to settle
# ----------------------------------------------------------------------
resource "time_sleep" "wait_after_metallb" {
  depends_on      = [terraform_data.apply_metallb_config]
  create_duration = "30s"
}

# ----------------------------------------------------------------------
# 19. Ingress NGINX Controller (single shared LoadBalancer IP)
# ----------------------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  version          = "4.11.3"
  create_namespace = true

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "metallb.universe.tf/address-pool" = "homelab-pool"
          }
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
    })
  ]

  depends_on = [time_sleep.wait_after_metallb]
}

# ----------------------------------------------------------------------
# 20. Output the external IP assigned to the Ingress controller
# ----------------------------------------------------------------------
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = helm_release.ingress_nginx.namespace
  }
  depends_on = [helm_release.ingress_nginx]
}

output "ingress_controller_ip" {
  value       = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
  description = "External IP of the Ingress controller (single shared IP for all web apps)"
}
