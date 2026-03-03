#!/bin/bash
set -e

PROXMOX_HOST="192.168.1.65"
SSH_KEY="$HOME/.ssh/proxmox-k3s"
VM_IDS=(105 106 107)

echo "=== Removing orphaned VMs from Proxmox ==="
for id in "${VM_IDS[@]}"; do
    if ssh -i "$SSH_KEY" root@$PROXMOX_HOST "qm status $id" 2>/dev/null; then
        echo "Stopping and destroying VM $id"
        ssh -i "$SSH_KEY" root@$PROXMOX_HOST "qm stop $id --skiplock 2>/dev/null || true"
        ssh -i "$SSH_KEY" root@$PROXMOX_HOST "qm destroy $id"
    else
        echo "VM $id does not exist, skipping"
    fi
done

echo "=== Removing orphaned resources from OpenTofu state ==="
for id in "${VM_IDS[@]}"; do
    # Remove each VM resource if it exists in the state
    tofu state rm "proxmox_virtual_environment_vm.control_plane" 2>/dev/null || true
    tofu state rm "proxmox_virtual_environment_vm.worker_1" 2>/dev/null || true
    tofu state rm "proxmox_virtual_environment_vm.worker_2" 2>/dev/null || true
done

echo "Cleanup complete. You can now run 'tofu apply'."