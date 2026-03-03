```bash
# Talos Kubernetes Cluster Bootstrap on Proxmox – Recovery Guide
# Run these commands on your management node (192.168.1.60) in order.
# All required OpenTofu files (providers.tf, variables.tf, main.tf, schematic.yaml) are assumed to be present in the current directory.

# 1. Ensure prerequisites are installed:
#    - OpenTofu (tofu) >= 1.6
#    - talosctl >= 1.5
#    - SSH key at ~/.ssh/proxmox-k3s (private) and authorized for root on Proxmox host 192.168.1.65.
#    - Proxmox API token (see below how to create).

# 2. Start ssh-agent and load your SSH key (required for the provider's fallback SSH operations).
eval $(ssh-agent -s)
ssh-add ~/.ssh/proxmox-k3s

# 3. Set the Proxmox API token environment variable.
#    Replace with your actual token string (format: USER@REALM!TOKENID=SECRET).
export TF_VAR_proxmox_api_token='terraform@pve!provider=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# 4. Initialize OpenTofu (downloads providers).
tofu init

# 5. Apply the configuration. This will:
#    - Download a custom Talos image with qemu-guest-agent.
#    - Create a template VM (ID 9999) from that image.
#    - Clone control plane (ID 107) and two worker VMs (IDs 105,106) with static IPs 192.168.1.61‑63.
#    - Generate Talos secrets and apply configurations.
#    - Wait for bootstrap and fetch kubeconfig.
tofu apply -auto-approve

# 6. After apply completes, wait a few minutes for the Kubernetes API server to become ready.
#    Monitor control plane services with:
talosctl --talosconfig talosconfig -n 192.168.1.61 services
#    Look for etcd, apiserver, kubelet to be 'Running'.

# 7. Verify cluster access:
kubectl --kubeconfig kubeconfig get nodes
#    If connection refused, wait longer and repeat step 6.

# 8. (Optional) If you need to re‑run the process from scratch, destroy everything:
#    tofu destroy -auto-approve
#    Then repeat from step 4.

# 9. (Optional) Merge kubeconfig into your default config:
#    mkdir -p ~/.kube
#    cp kubeconfig ~/.kube/config

# ----- Proxmox API Token Creation (one‑time) -----
# On Proxmox host (192.168.1.65):
# pveum user add terraform@pve
# pveum role add TerraformRole -privs "VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.PowerMgmt Datastore.AllocateSpace Datastore.AllocateTemplate"
# pveum acl modify / -user terraform@pve -role TerraformRole
# pveum user token add terraform@pve provider --privsep=0
# Copy the full token string (including the secret) for TF_VAR_proxmox_api_token.
```