resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "privileged"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "privileged"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

locals {
  longhorn_tolerations = [
    {
      key      = "storage"
      operator = "Equal"
      value    = "local-block"
      effect   = "NoSchedule"
    },
  ]

  longhorn_node_selector = {
    "storage.capability" = "local-block"
  }
}

resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  namespace        = kubernetes_namespace.longhorn_system.metadata[0].name
  create_namespace = false
  version          = "1.7.2"
  timeout          = 900

  depends_on = [
    kubernetes_namespace.longhorn_system,
    kubernetes_labels.worker_longhorn,
    kubernetes_annotations.worker_longhorn_disks,
  ]

  values = [
    yamlencode({
      preUpgradeChecker = {
        jobEnabled = false
      }

      longhornManager = {
        nodeSelector = local.longhorn_node_selector
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }

      longhornDriver = {
        nodeSelector = local.longhorn_node_selector
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }

      longhornUI = {
        nodeSelector = local.longhorn_node_selector
      }

      longhornAdmissionWebhook = {
        nodeSelector = local.longhorn_node_selector
      }

      longhornRecoveryBackend = {
        nodeSelector = local.longhorn_node_selector
      }

      persistence = {
        defaultClass           = false
        defaultDataPathEnabled = false
      }

      defaultSettings = {
        defaultReplicaCount = 1
        replicaAutoBalance  = "least-effort"
        defaultNodeSelector = "storage.capability=local-block"
      }
    })
  ]
}

resource "kubernetes_storage_class" "longhorn_sc" {
  metadata {
    name = "longhorn-sc"
  }

  storage_provisioner    = "driver.longhorn.io"
  allow_volume_expansion = true
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"

  parameters = {
    numberOfReplicas    = "1"
    staleReplicaTimeout = "2880"
    fsType              = "ext4"
    # nodeSelector removed – defaultSettings.defaultNodeSelector already
    # restricts replicas to nodes with the storage.capability=local-block label.
  }

  depends_on = [helm_release.longhorn]
}

resource "kubernetes_annotations" "worker_longhorn_disks" {
  force = true

  for_each = {
    for name, w in local.workers : name => w
    if length(w.longhorn_disks) > 0
  }

  api_version = "v1"
  kind        = "Node"

  metadata {
    name = "${local.cluster_name}-${each.key}"
  }

  annotations = {
    "node.longhorn.io/default-disks-config" = jsonencode([
      for slot, spec in each.value.longhorn_disks : {
        path            = "/var/mnt/longhorn-${slot}"
        allowScheduling = true
        tags            = []
        storageReserved = 0
      }
    ])
  }
}