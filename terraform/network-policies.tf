resource "kubernetes_manifest" "allow_dns_egress" {
  depends_on = [null_resource.wait_for_api]
  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumClusterwideNetworkPolicy"
    metadata   = { name = "allow-dns-egress" }
    spec = {
      endpointSelector = {}
      egress = [
        {
          toServices = [{
            k8sService = {
              serviceName = "kube-dns"
              namespace   = "kube-system"
            }
          }]
          toPorts = [{ ports = [{ port = "53", protocol = "ANY" }] }]
        },
        {
          toEntities = ["world", "cluster", "host"]
        }
      ]
    }
  }
}

# TODO: replace the above broad policy with least privilage access

# ----------------------------------------------------------------------
# Wait for cluster to stabilise after Talos config changes
# ----------------------------------------------------------------------
# resource "time_sleep" "wait_after_talos_apply" {
#   depends_on = [
#     talos_machine_configuration_apply.controlplane,
#     talos_machine_configuration_apply.worker[0],
#     talos_machine_configuration_apply.worker[1],
#     talos_machine_configuration_apply.worker[2]
#   ]
#   create_duration = "10s"
# }

# ----------------------------------------------------------------------
# Allow all pods to resolve DNS and reach Authentik (IDP)
# # ----------------------------------------------------------------------
# resource "kubernetes_manifest" "allow_authentik_egress" {
#   depends_on = [
#     null_resource.wait_for_api,
#     time_sleep.wait_after_talos_apply
#   ]

#   manifest = {
#     apiVersion = "cilium.io/v2"
#     kind       = "CiliumClusterwideNetworkPolicy"
#     metadata = {
#       name = "allow-authentik-egress"
#     }
#     spec = {
#       endpointSelector = {} # applies to all pods
#       egress = [
#         {
#           toServices = [
#             {
#               k8sService = {
#                 serviceName = "kube-dns"
#                 namespace   = "kube-system"
#               }
#             }
#           ]
#           toPorts = [
#             {
#               ports = [
#                 { port = "53", protocol = "ANY" }
#               ]
#             }
#           ]
#         },
#         {
#           toFQDNs = [
#             {
#               matchName = "authentik.nase.dev"
#             }
#           ]
#           toPorts = [
#             {
#               ports = [
#                 { port = "443", protocol = "TCP" }
#               ]
#             }
#           ]
#         }
#       ]
#     }
#   }
# }
