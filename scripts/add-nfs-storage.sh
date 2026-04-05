#!/bin/bash
# Script to add TrueNAS NFS share as Proxmox storage (k3s-storage)
# Run this directly on Proxmox node (pve01)

set -e  # Exit on any error

# Configuration - EDIT THESE VALUES
TRUE_NAS_IP="192.168.1.32"
NFS_EXPORT="/mnt/Uldaman/proxmox-vms"
STORAGE_ID="k3s-storage"
CONTENT_TYPES="images,iso,vztmpl,backup"
MOUNT_OPTIONS="vers=4.2,hard,intr,rsize=1048576,wsize=1048576"

echo "🔧 Adding NFS storage '$STORAGE_ID' from TrueNAS ($TRUE_NAS_IP:$NFS_EXPORT)"

# Step 1: Install NFS client if not present
if ! command -v mount.nfs4 &> /dev/null; then
    echo "📦 Installing nfs-common..."
    apt update && apt install -y nfs-common
fi

# Step 2: Test basic connectivity to NFS port
echo "🔍 Testing connectivity to NFS port 2049..."
if nc -zv "$TRUE_NAS_IP" 2049 2>&1 | grep -q succeeded; then
    echo "✅ NFS port reachable"
else
    echo "❌ Cannot reach NFS port 2049 on $TRUE_NAS_IP"
    exit 1
fi

# Step 3: Attempt a manual mount to verify the export is working
echo "🔍 Attempting manual mount to verify export..."
MOUNT_POINT_TEST="/mnt/test-truenas"
mkdir -p "$MOUNT_POINT_TEST"
if mount -t nfs4 -o "$MOUNT_OPTIONS" "$TRUE_NAS_IP:$NFS_EXPORT" "$MOUNT_POINT_TEST"; then
    echo "✅ Manual mount successful – NFS export is accessible"
    umount "$MOUNT_POINT_TEST"
    rmdir "$MOUNT_POINT_TEST"
else
    echo "❌ Manual mount failed. Check:"
    echo "   - Dataset $NFS_EXPORT exists on TrueNAS"
    echo "   - NFS service is running"
    echo "   - Export is shared with 192.168.1.0/24"
    echo "   - Maproot user is set to 'root'"
    exit 1
fi

# Step 4: Add storage using pvesm
echo "➕ Adding storage via pvesm..."
pvesm add nfs "$STORAGE_ID" \
    --server "$TRUE_NAS_IP" \
    --export "$NFS_EXPORT" \
    --content "$CONTENT_TYPES" \
    --options "$MOUNT_OPTIONS" \
    --shared 1

# Step 5: Verify storage was added
echo "✅ Verifying storage..."
pvesm status | grep "$STORAGE_ID" || {
    echo "❌ Storage added but not visible in status"
    exit 1
}

# Step 6: Show mount point
MOUNT_POINT="/mnt/pve/$STORAGE_ID"
echo "📂 Storage mounted at: $MOUNT_POINT"
df -h "$MOUNT_POINT" || echo "⚠️  Mount point not yet active (may need moment)"

echo "🎉 Success! NFS storage '$STORAGE_ID' is ready."