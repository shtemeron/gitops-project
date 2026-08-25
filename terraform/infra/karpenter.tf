# Stage 8 — Karpenter's AWS-API-only prerequisites. The controller
# itself (Helm chart) and its NodePool/EC2NodeClass CRDs are installed
# via ArgoCD (k8s-apps/argocd-apps/karpenter.yaml) — not a Terraform
# bootstrapping dependency, same reasoning as Kyverno in Stage 7. What
# lives here is only what needs AWS APIs, never the K8s API: the node
# instance profile and the Spot-interruption-handling plumbing (SQS +
# EventBridge). The controller's own IRSA role lives in platform/,
# since it needs infra/'s OIDC provider output — same split as every
# other IRSA role in this project.
#
# Everything below is transcribed directly from Karpenter's own
# official getting-started CloudFormation template
# (github.com/aws/karpenter-provider-aws, v1.14.1,
# website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml)
# rather than hand-reconstructed — same practice as the LB Controller's
# IAM policy in Stage 6.

# Node identity reuses the existing managed-node-group IAM role
# (aws_iam_role.eks_node in eks.tf) rather than duplicating a parallel
# one — the actual required policies for any EKS worker node (managed
# or Karpenter-provisioned) are identical. No instance profile created
# here: EC2NodeClass references this role by name
# (spec.role, not spec.instanceProfile), and Karpenter's controller
# creates/manages the instance profile itself dynamically — the
# standard, documented pattern, and exactly what the
# IAMIntegrationPolicy permissions (CreateInstanceProfile/
# TagInstanceProfile/etc., copied into platform/karpenter.tf) are for.

# EC2NodeClass discovers the security group to attach to Karpenter-
# provisioned nodes by this same tag (see vpc.tf's private subnets for
# the subnet-side half) — tagging the cluster's own auto-created
# security group directly, so Karpenter nodes get identical network
# reachability to the existing managed node group without duplicating
# a parallel security group.
resource "aws_ec2_tag" "karpenter_discovery_sg" {
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.project_name
}

# --- Spot interruption handling — SQS queue + EventBridge rules feeding
# it. Karpenter's controller (platform/) polls this queue and drains
# pods gracefully on a real interruption/rebalance signal, rather than
# losing them abruptly when AWS reclaims a Spot instance. ---

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = var.project_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

data "aws_iam_policy_document" "karpenter_interruption_queue" {
  statement {
    sid    = "EC2InterruptionPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue.json
}

locals {
  karpenter_interruption_events = {
    scheduled_change         = { source = "aws.health", detail_type = "AWS Health Event" }
    spot_interruption         = { source = "aws.ec2", detail_type = "EC2 Spot Instance Interruption Warning" }
    rebalance                 = { source = "aws.ec2", detail_type = "EC2 Instance Rebalance Recommendation" }
    instance_state_change     = { source = "aws.ec2", detail_type = "EC2 Instance State-change Notification" }
    capacity_reservation      = { source = "aws.ec2", detail_type = "EC2 Capacity Reservation Instance Interruption Warning" }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  name = "${var.project_name}-karpenter-${each.key}"
  event_pattern = jsonencode({
    source      = [each.value.source]
    detail-type = [each.value.detail_type]
  })
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  rule = aws_cloudwatch_event_rule.karpenter_interruption[each.key].name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}
