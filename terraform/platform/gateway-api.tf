# Gateway API CRDs — not a Helm chart, applied directly from the
# upstream release manifest, the standard/official install method (same
# as any real team would use). "standard" channel, not "experimental" —
# GatewayClass/Gateway/HTTPRoute/ReferenceGrant are all GA-stable;
# TCPRoute/TLSRoute (experimental-only) aren't needed here. No
# destroy-time cleanup needed: CRDs live in the cluster's own etcd, so a
# full infra/ teardown (which destroys the whole EKS cluster) removes
# them implicitly — nothing to orphan.
resource "null_resource" "gateway_api_crds" {
  triggers = {
    version = "v1.6.1"
  }

  provisioner "local-exec" {
    command = "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml"
  }
}
