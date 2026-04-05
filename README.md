# Talos Cluster Boostrap Infrastructure

This project serves to bootstrap a Kubernetes cluster running a CI/CD pipeline.

## Stack and Dependencies

### OpenTofu Providers

- [OpenTofu](https://github.com/opentofu/opentofu) – Infrastructure as code tool (fork of Terraform)
- [Talos Linux](https://github.com/siderolabs/talos) – Immutable OS for Kubernetes
- [BPG Proxmox Provider](https://github.com/bpg/terraform-provider-proxmox) – OpenTofu provider for Proxmox VE
- [Talos Provider](https://github.com/siderolabs/terraform-provider-talos) – OpenTofu provider for Talos Linux
- [Helm Provider](https://github.com/hashicorp/terraform-provider-helm) – OpenTofu provider for Helm charts
- [Kubernetes Provider](https://github.com/hashicorp/terraform-provider-kubernetes) – OpenTofu provider for Kubernetes API
- [Time Provider](https://github.com/hashicorp/terraform-provider-time) – OpenTofu utility provider for time delays
- [Local Provider](https://github.com/hashicorp/terraform-provider-local) – OpenTofu provider for managing local files
- [Null Provider](https://github.com/hashicorp/terraform-provider-null) – OpenTofu utility provider for placeholders
- [Cilium](https://github.com/cilium/cilium) – CNI and network observability for Kubernetes
- [Hubble](https://docs.cilium.io/en/stable/observability/hubble/#hubble-intro)

## Prerequisites

### TrueNAS
```bash
# Create NFS share (run on Proxmox host)
./add-nfs-storage.sh

# Remove existing storage if necessary
pvesm remove k3s-storage

# Create storage share
root@pve01:~# pvesm add nfs k3s-storage \
  --server 192.168.1.32 \
  --export /mnt/Uldaman/k8s \
  --content images,iso,vztmpl,backup \
  --options "vers=3,hard,intr,rsize=1048576,wsize=1048576"

zfs create Uldaman/k8s/nfs
zfs create -o org.freenas:description="K8s NFS volumes" Uldaman/k8s/nfs/v
zfs create -o org.freenas:description="K8s NFS snapshots" Uldaman/k8s/nfs/s
```

## "Quickstart"

```bash
# =============================================================================
# Quickstart for a fresh Proxmox host (run as root)
# =============================================================================

# 1. Install essential tools
apt update
apt install -y git make curl

# 2. Generate the SSH key that the Makefile expects (default: ~/.ssh/proxmox-k3s)
if [ ! -f ~/.ssh/proxmox-k3s ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/proxmox-k3s
fi

# 3. Authorize the public key for localhost (so SSH to 127.0.0.1 works)
cat ~/.ssh/proxmox-k3s.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 4. (Optional) If your Proxmox IP is not 192.168.1.65, export it
# export PROXMOX_HOST="your_proxmox_ip"

# 5. Clone your bootstrap repository (adjust URL if needed)
git clone https://gitlab.atomic6.net/nase/talos-cluster-bootstrap.git
cd talos-cluster-bootstrap

# 6. (Optional) Test SSH connectivity
ssh -o BatchMode=yes -o ConnectTimeout=5 127.0.0.1 "exit" && echo "SSH OK" || echo "SSH failed"

# 7. Run the fully automated bootstrap
#    The Makefile will install missing tools, create a Proxmox API token (if none exists),
#    and apply the Terraform configuration.
make bootstrap

# 8. After completion, verify the cluster
kubectl --kubeconfig kubeconfig get nodes
```

### Tooling
```bash
# 1. Install required tools
# Add OpenTofu repository
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo bash
# Install talosctl
curl -sL https://talos.dev/install | sh
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# Install git (if not present)
sudo apt update && sudo apt install -y git

# 2. Clone the project repository (replace with your actual repo URL)
git clone https://github.com/yourusername/talos-proxmox.git
cd talos-proxmox
```

### Environment
```bash
# 3. Set up environment variables for Proxmox authentication
export TF_VAR_proxmox_api_token="USER@pve!TOKEN_NAME=UUID-SECRET"
export TF_VAR_proxmox_ssh_private_key_path="$HOME/.ssh/id_rsa"  # or your key path

# Optional: Load SSH key into agent if using agent
eval $(ssh-agent) && ssh-add ~/.ssh/id_rsa
```

## Initialize

### Bootstrap Kubernetes cluster
```bash
# 4. Initialize OpenTofu
tofu init

# 5. Phase 1 – Deploy Talos cluster and fetch kubeconfig
tofu apply -auto-approve

# 6. Phase 2 – Install Cilium CNI (and any other addons)
tofu apply -auto-approve

# 7. Verify cluster
export KUBECONFIG=./kubeconfig
kubectl get nodes
kubectl -n kube-system get pods
```

## Clean slate
```bash
tofu destroy -auto-approve

# List all resources currently in state
tofu state list

# Remove any remaining VMs (if any besides control plane)
tofu state rm proxmox_virtual_environment_vm.control_plane

# Also remove any leftover download files that might be causing conflicts
tofu state list | grep talos_iso | xargs -r tofu state rm

# Destroy Talos nocloud image, will prompt re-download upon nexttofu apply
rm /mnt/pve/k3s-storage/template/iso/talos-ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515-v1.9.5-nocloud-amd64.raw.img
```

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