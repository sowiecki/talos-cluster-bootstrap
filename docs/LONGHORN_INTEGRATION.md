# LONGHORN_INTEGRATION.md

## Adding Longhorn to Additional Worker Nodes

This runbook describes how to extend Longhorn storage capability to an existing
worker node in the cluster, one node at a time. It follows the same pattern
used for `worker-5` and assumes the Terraform configuration in
`terraform/` is the source of truth.

**Prerequisites:**
- The target worker is already part of the Kubernetes cluster and shows `Ready`
  in `kubectl get nodes`.
- You have SSH access to the Proxmox host that runs the worker.
- The Proxmox host has available block devices or free space in an existing
  LVM-thin pool that can be dedicated to Longhorn.
- `tofu` and `kubectl` are configured against the cluster.

---

## 1. Determine the storage layout on the Proxmox host

Log into the Proxmox host that runs the target worker. For this example, the
target is `worker-1` on `pve02`.

```bash
ssh root@pve02
```

List all disks and their current usage:

```bash
lsblk -d -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL,SERIAL
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL,SERIAL
```

Identify the disks that will be dedicated to Longhorn. Confirm they are truly
empty — no partition table, no filesystem, no LVM header:

```bash
blkid /dev/sdX /dev/sdY    # replace with the actual device names
```

If `blkid` prints nothing for those devices, they are safe to use. If it
prints anything, stop and investigate before proceeding.

Check which Proxmox storage pools are already registered:

```bash
pvesm status
cat /etc/pve/storage.cfg
```

Decide whether to:

- **Reuse an existing LVM-thin pool** (e.g. `local-lvm` on the host's primary
  disk), by slicing a chunk of it for Longhorn. This is the simplest path and
  is what `worker-5` does for its primary Longhorn disk.
- **Create a new LVM-thin pool** on dedicated disks, as was done on `pve06`
  with the three SATA SSDs. Use this if you want Longhorn isolated from the
  host's primary storage.

---

## 2. (Optional) Create a dedicated LVM-thin pool on the Proxmox host

Skip this step if you are reusing an existing pool.

```bash
# Wipe residual signatures (only on confirmed-empty disks)
wipefs -a /dev/sdX /dev/sdY

# Create the volume group
vgcreate longhorn-vg /dev/sdX /dev/sdY

# Create the thin pool inside it
lvcreate --type thin-pool \
  --poolmetadatasize 1G \
  --chunksize 256K \
  -l 95%FREE \
  -n longhorn-pool longhorn-vg

# Register the pool with Proxmox
pvesm add lvmthin longhorn-lvm \
  --vgname longhorn-vg \
  --thinpool longhorn-pool \
  --content images,rootdir
```

Verify:

```bash
pvs
vgs
lvs
pvesm status
```

The new pool should appear as `active`.

---

## 3. Update `locals.tf` for the target worker

Open `terraform/locals.tf`. Locate the `workers` map. For the target worker
(e.g. `worker-1`), replace the empty `longhorn_disks = {}` with the disk
layout you want.

Example — one Longhorn disk carved from `local-lvm`:

```hcl
worker-1 = {
  proxmox_node   = "pve02"
  ip             = "192.168.1.62"
  vm_id          = 106
  mac_address    = "BC:24:11:00:00:62"
  cores          = 10
  memory         = 14000
  os_disk_size   = 950
  node_class     = "standard"
  kubelet_args   = {}
  sysctls        = {}
  longhorn_disks = {
    scsi1 = { datastore = "local-lvm", size = 260, device = "/dev/sdb" }
  }
  talos_version_override = null
  schematic_id_override  = null
}
```

Example — three Longhorn disks backed by a dedicated `longhorn-lvm` pool:

```hcl
longhorn_disks = {
  scsi1 = { datastore = "longhorn-lvm", size = 110, device = "/dev/sdb" }
  scsi2 = { datastore = "longhorn-lvm", size = 110, device = "/dev/sdc" }
  scsi3 = { datastore = "longhorn-lvm", size = 110, device = "/dev/sdd" }
}
```

**Important notes:**

- The `device` value is what Talos will see inside the VM. Verify with
  `talosctl get disks` after the first boot before trusting it.
- `scsi0` is always the OS disk. Longhorn data disks start at `scsi1`.
- If the worker does not yet have `storage-local-block` in its tags, the
  conditional in `workers.tf` will add it automatically because
  `longhorn_disks` is now non-empty.

---

## 4. Update `workers.tf` if the schematic needs to change

The `talos_image_factory_schematic.this` resource is shared across all workers.
If the target worker is running an older Talos version that lacks the
`iscsi-tools` fix, you have two options:

**Option A — Upgrade the worker to v1.13.11+ as part of this change.**

Add a `talos_version_override` to the worker's entry in `locals.tf`:

```hcl
talos_version_override = "v1.13.11"
```

Then, after applying, run the upgrade manually:

```bash
talosctl --talosconfig talosconfig --nodes <worker-ip> upgrade \
  --image "factory.talos.dev/installer/<schematic-id>:v1.13.11"
```

**Option B — Add a per-worker schematic override.**

If you want to keep the worker on its current Talos version and only add the
extensions, add a `schematic_id_override` pointing at a new schematic ID that
includes `iscsi-tools` and `util-linux-tools`. This is only useful if the
worker's Talos version already supports the extension paths Longhorn checks.

---

## 5. Plan the change

From the `terraform/` directory:

```bash
rm -f add-longhorn-worker-N.tfplan
tofu plan -out=add-longhorn-worker-N.tfplan
```

Review the plan carefully. It should show:

- `proxmox_virtual_environment_vm.worker["worker-N"]` — **update in-place**,
  adding a `disk` block for each `longhorn_disks` entry.
- `talos_machine_configuration_apply.worker["worker-N"]` — **update in-place**,
  with a changed `machine_configuration_hash`.
- `talos_machine_configuration.worker["worker-N"]` — **read**, resolved with the
  new disk mountpoints and `nodeAnnotations`.
- No changes to any other worker's VM or config resources.
- No changes to the control plane.

If any other resource appears in the plan with a destructive action, stop and
investigate before applying.

**Do not apply the plan yet.** Stop after reviewing it and confirm with
yourself that the only affected VM is the one you intend to modify.

---

## 6. Apply the change

When satisfied:

```bash
tofu apply add-longhorn-worker-N.tfplan
```

The Talos config apply will restart kubelet on the target worker. Any pods
running on that worker will be rescheduled if they cannot tolerate the brief
disruption. For a worker with no Longhorn-related workloads yet, this is a
no-op.

---

## 7. Verify the worker joined Longhorn

Wait 30–60 seconds, then check:

```bash
kubectl -n longhorn-system get nodes.longhorn.io
```

You should see a new entry named `nase-dev-prod-worker-N` (the full Kubernetes
node name), with `READY: True`, `ALLOWSCHEDULING: true`, and
`SCHEDULABLE: True`.

If the entry is missing:

```bash
kubectl -n longhorn-system describe nodes.longhorn.io nase-dev-prod-worker-N
kubectl -n longhorn-system logs -l app=longhorn-manager --tail=50 | grep -i worker-N
```

Common causes:

- The `node.longhorn.io/create-default-disk=config` label or the matching
  annotation is missing from the Kubernetes node object.
- The disk device paths in the machine config do not match what Talos actually
  sees. Check with:

  ```bash
  talosctl --talosconfig talosconfig --nodes <worker-ip> get disks
  ```

- The Longhorn manager has not yet reconciled. Restart it:

  ```bash
  kubectl -n longhorn-system rollout restart daemonset longhorn-manager
  ```

---

## 8. Verify Longhorn picked up the disks

Once the node object exists:

```bash
kubectl -n longhorn-system get nodes.longhorn.io nase-dev-prod-worker-N -o yaml
```

Under `spec.disks`, you should see one entry per `longhorn_disks` entry in the
Terraform config, each with:

- `allowScheduling: true`
- `path: /var/mnt/longhorn-<scsi-slot>`
- A non-zero `storageMaximum` and `storageAvailable`

If a disk shows `allowScheduling: false` or zero capacity, the mountpoint may
not have been created. Verify on the node:

```bash
talosctl --talosconfig talosconfig --nodes <worker-ip> get mounts
```

The `/var/mnt/longhorn-*` paths should be listed with the expected size.

---

## 9. Increase replica count on existing volumes (if desired)

Once the new worker is healthy and schedulable, you can increase the replica
count on any existing Longhorn volume without detaching it:

```bash
kubectl -n longhorn-system patch volume.longhorn.io <volume-name> \
  -p '{"spec":{"numberOfReplicas":2}}' --type=merge
```

Longhorn will begin rebuilding a new replica on the new worker while the
volume remains attached. No downtime.

To find volume names:

```bash
kubectl -n longhorn-system get volumes.longhorn.io
```

---

## 10. Update the StorageClass (optional)

If you want *new* volumes to have a higher replica count, update the
`numberOfReplicas` parameter in `longhorn.tf`:

```hcl
parameters = {
  numberOfReplicas    = "2"
  staleReplicaTimeout = "2880"
  fsType              = "ext4"
}
```

Because StorageClass `parameters` are immutable, Terraform will destroy and
recreate the StorageClass. This does **not** affect existing PVCs or PVs — only
new provisioning requests.

---

## Rollback

If something goes wrong on the target worker and you need to revert:

1. Revert the `longhorn_disks` entry in `locals.tf` back to `{}`.
2. Plan and apply. This will remove the data disks from the VM definition.
   The `ignore_changes = [disk]` lifecycle on the VM resource means the disks
   will **not** be detached from the running VM without an explicit destroy
   and recreate — so the change is safe.
3. On the Proxmox host, the volumes created for those disks will remain.
   Delete them manually if you want to reclaim the space:

   ```bash
   pvesm list <storage-pool>
   # identify the vm-<vmid>-disk-<n> volumes
   pvesm free <volume-id>
   ```

4. Remove the Longhorn node if it is still registered:

   ```bash
   kubectl -n longhorn-system delete nodes.longhorn.io nase-dev-prod-worker-N
   ```

---

## Checklist (per node)

- [ ] Proxmox host has the target disks or pool space ready.
- [ ] `blkid` confirms target disks are empty (if creating a new pool).
- [ ] `longhorn_disks` entry added to `locals.tf` for the target worker.
- [ ] `tofu plan` reviewed; only the target worker is affected.
- [ ] `tofu apply` completed successfully.
- [ ] `kubectl -n longhorn-system get nodes.longhorn.io` shows the new node as
      `READY True`, `SCHEDULABLE True`.
- [ ] `spec.disks` on the new node object shows the expected disks with
      `allowScheduling: true`.
- [ ] (Optional) Replica count raised on existing volumes.
- [ ] (Optional) StorageClass `numberOfReplicas` updated for new volumes.
