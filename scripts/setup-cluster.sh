#!/bin/bash
set -euo pipefail

# Ensure we use the correct kubeconfig (relative to the script's execution directory)
export KUBECONFIG="./kubeconfig"

CONTROL_PLANE_IP="192.168.1.61"
API_URL="https://${CONTROL_PLANE_IP}:6443"

# Helper function to run a command with retries on certificate errors
retry_on_cert_error() {
  local max_retries=10
  local retry_delay=5
  local attempt=1
  local cmd="$*"
  while [ $attempt -le $max_retries ]; do
    if eval "$cmd" 2>&1; then
      return 0
    else
      local exit_code=$?
      # If the error contains "certificate has expired or is not yet valid", retry
      if [[ $? -ne 0 && "${PIPESTATUS[0]}" -ne 0 ]]; then
        # Need to capture the error message from the command
        # We'll rely on the fact that the command's stderr contains the certificate error
        # For simplicity, we'll just retry on any failure, but we can be more precise.
        # Since we know the specific error, we'll check the last output.
        local last_error="$(eval "$cmd" 2>&1 | tail -n 1)"
        if [[ "$last_error" =~ "certificate has expired or is not yet valid" ]]; then
          echo "Certificate not yet valid (attempt $attempt/$max_retries). Retrying in ${retry_delay}s..."
          sleep $retry_delay
          attempt=$((attempt+1))
          continue
        else
          # Other error, fail immediately
          echo "Command failed with: $last_error"
          return $exit_code
        fi
      else
        return $exit_code
      fi
    fi
  done
  echo "Failed after $max_retries attempts."
  return 1
}

echo "=================================================="
echo "Waiting for Kubernetes API to be reachable..."
for i in {1..120}; do
  if kubectl --insecure-skip-tls-verify get nodes &>/dev/null; then
    echo "API is reachable."
    break
  fi
  if curl -k -s "${API_URL}/version" &>/dev/null; then
    echo "API endpoint is up but kubectl fails, retrying..."
  fi
  echo "Attempt $i: API not ready, waiting 5s..."
  sleep 5
  if [ $i -eq 120 ]; then
    echo "ERROR: API not reachable after 10 minutes. Diagnosing..."
    echo "Kubeconfig content:"
    cat "${KUBECONFIG}" || echo "kubeconfig not found"
    echo "Attempting curl to API:"
    curl -k -v "${API_URL}/version" 2>&1 | head -20
    exit 1
  fi
done

echo "=================================================="
echo "Installing Helm charts..."
helm repo add cilium https://helm.cilium.io/ --force-update
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ --force-update
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo update

echo "Installing Cilium..."
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.19.1 \
  --set kubeProxyReplacement=true \
  --set routingMode=tunnel \
  --set tunnelProtocol=geneve \
  --set k8sServiceHost="${CONTROL_PLANE_IP}" \
  --set k8sServicePort=6443 \
  --set hostServices.enabled=true \
  --set socketLB.enabled=true \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set endpointRoutes.enabled=true \
  --set ipv4.enabled=true \
  --set ipv6.enabled=false \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set securityContext.privileged=true \
  --set initSecurityContext.privileged=true \
  --set cni.uninstall=false \
  --insecure-skip-tls-verify

echo "Waiting for Cilium pods to be ready..."
kubectl --insecure-skip-tls-verify wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s

# Retry for NFS CSI installation (may fail due to certificate not yet valid)
echo "Installing NFS CSI driver..."
retry_on_cert_error "helm upgrade --install nfs-csi nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace kube-system \
  --version 4.0.18 \
  --set nfs.server=192.168.1.32 \
  --set nfs.path=/mnt/Uldaman/k8s/nfs/v \
  --set storageClass.name=truenas-nfs \
  --set storageClass.defaultClass=true \
  --set storageClass.reclaimPolicy=Delete \
  --set storageClass.allowVolumeExpansion=true \
  --set storageClass.mountOptions[0]=nfsvers=4 \
  --set storageClass.mountOptions[1]=hard \
  --set storageClass.mountOptions[2]=noatime \
  --insecure-skip-tls-verify"

# Retry for Ingress NGINX installation
echo "Installing Ingress NGINX..."
retry_on_cert_error "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version 4.11.3 \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."metallb\.universe\.tf/address-pool"=homelab-pool \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=128Mi \
  --set controller.allowSnippetAnnotations=true \
  --insecure-skip-tls-verify"

echo "=================================================="
echo "Waiting for Cilium CRDs..."
for i in {1..60}; do
  if kubectl --insecure-skip-tls-verify get crd ciliumnetworkpolicies.cilium.io &>/dev/null; then
    echo "Cilium CRDs ready."
    break
  fi
  sleep 5
done

echo "Applying CoreDNS RBAC..."
kubectl --insecure-skip-tls-verify apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:coredns
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
rules:
- apiGroups: [""]
  resources: ["endpoints", "services", "pods", "namespaces"]
  verbs: ["list", "watch"]
- apiGroups: ["discovery.k8s.io"]
  resources: ["endpointslices"]
  verbs: ["list", "watch"]
EOF

kubectl --insecure-skip-tls-verify apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:coredns
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
EOF

echo "Applying CiliumNetworkPolicies..."
kubectl --insecure-skip-tls-verify apply -f - <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-coredns-to-kubeapi
  namespace: kube-system
spec:
  endpointSelector:
    matchLabels:
      k8s-app: kube-dns
  egress:
  - toEntities:
    - kube-apiserver
EOF

kubectl --insecure-skip-tls-verify apply -f - <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-coredns-external
  namespace: kube-system
spec:
  endpointSelector:
    matchLabels:
      k8s-app: kube-dns
  egress:
  - toCIDR:
    - 192.168.1.1/32
    - 192.168.1.100/32
    - 1.1.1.1/32
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
  - toFQDNs:
    - matchName: gitlab-charts.s3.amazonaws.com
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
EOF

echo "=================================================="
echo "Installing MetalLB..."
kubectl --insecure-skip-tls-verify apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

echo "Waiting for MetalLB webhook to be ready..."
for i in {1..60}; do
  if kubectl --insecure-skip-tls-verify get pods -n metallb-system -l app=metallb,component=webhook -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q True; then
    echo "Webhook ready."
    break
  fi
  sleep 5
done

echo "Applying MetalLB IPAddressPool and L2Advertisement..."
kubectl --insecure-skip-tls-verify apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.21-192.168.1.30
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab
  namespace: metallb-system
spec:
  ipAddressPools:
  - homelab-pool
EOF

echo "=================================================="
echo "Restarting CoreDNS to pick up new RBAC and policies..."
kubectl --insecure-skip-tls-verify delete pods -n kube-system -l k8s-app=kube-dns
echo "Waiting for CoreDNS to be ready..."
kubectl --insecure-skip-tls-verify wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=180s

echo "=================================================="
echo "Cluster setup complete."