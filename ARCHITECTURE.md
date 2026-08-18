# Portfolio Project — Architecture & Build Plan

Design doc carried over from the `eks-argocd-project` learning roadmap
(complete as of this writing — see that repo's `ROADMAP_PROGRESS.md`).
This file exists so a brand-new Claude Code session, in a brand-new
repo, has full context without needing the old conversation history.

**Copy this file to the new repo's root as the first commit.** Point a
fresh Claude Code session at that repo and have it read this file
first.

---

## Purpose

A portfolio project for mid-level DevOps engineer interviews. Goal:
demonstrate breadth (every major skill from the prior learning roadmap)
*and* depth (real, defensible design decisions, not a checklist) in
one coherent, deployable system.

**Explicit working agreement carried over from the design conversation:
explain each stage in full before writing any code for it.** Build
incrementally, stage by stage, with understanding checked at each step
— this is a deliberate choice, not a formality, so the resulting
project can actually be defended in an interview.

## The concept, in one sentence

A small **URL-shortener service** (stateless API + Postgres backend)
running in two isolated environments — **dev** and **prod** — on one
EKS cluster, modeled as if two separate teams own them and genuinely
cannot touch each other's resources, with a full path from `git push`
to a publicly-reachable, monitored, autoscaling endpoint.

Why this app: small enough to explain in two minutes, but has exactly
two component shapes (stateless tier needing external access/HPA/
Karpenter, stateful tier needing storage/internal DNS) that make
nearly every required technology load-bearing instead of decorative.

## Two interpretation calls made during design — confirm or revise

1. **"dev/prod, each team cannot use the other's namespace"** — read as
   two *environments* of the same app, RBAC-isolated from each other
   as if owned by different teams. Not a generic multi-tenancy demo —
   the story is "the CI credential that deploys dev cannot touch prod,
   structurally, not by convention."
2. **"internal connection between pods... visible by static name
   (external DNS)"** — read literally: the backend resolves Postgres
   via a real custom name on a **private Route 53 zone** through
   `external-dns`, not a bare in-cluster Service name. A deliberate,
   explainable choice over the simpler default.

## Technology → role mapping (nothing included without a job)

| Requirement | Role in this design |
|---|---|
| Namespaces + ServiceAccounts, dev/prod isolation | RBAC boundary between environments — built *first*, foundation not afterthought |
| NetworkPolicy | Default-deny + explicit allow within each namespace, explicit deny *between* dev/prod — network-layer proof the RBAC story is real |
| Kyverno | Non-root, resource limits, no `:latest` — enforced from day one on both namespaces |
| Internal DNS / external-dns | Backend → Postgres via a stable private Route 53 name |
| Gateway API + AWS LB Controller | The one public entry point per environment — no classic Ingress |
| External connectivity verification | Two layers: CI post-deploy smoke test (immediate) + Blackbox Exporter probe feeding a Grafana uptime panel/alert (continuous) |
| StorageClass / PVC | Postgres via `StatefulSet` + `volumeClaimTemplates`; deliberate `Retain` (prod) vs `Delete` (dev) split |
| ConfigMaps | App config, kept deliberately separate from ESO-managed Secrets |
| AWS Secrets Manager + ESO | DB credentials |
| S3 | Loki's storage backend, S3-backed — a deliberate upgrade over the prior project's filesystem-mode choice, with a real durability-vs-simplicity tradeoff to explain |
| Prometheus + Grafana | App/platform metrics + the uptime panel above |
| HPA + Karpenter | Wired to the real app's real traffic, not a synthetic demo workload |
| GitHub Actions | Build → Trivy scan → push ECR → auto-deploy dev → **manual-approval promotion to prod** via GitHub Environments |
| Terraform + Helm | Terraform for AWS infra; the app itself packaged as a real Helm chart |

## Stage order

1. Architecture finalization (this document) — confirm concept + repo layout, no code
2. Terraform foundations — VPC + EKS + S3 + Secrets Manager
3. GitOps bootstrap — ArgoCD, ESO + ClusterSecretStore, decide App-of-Apps vs. `ApplicationSet` for dev/prod
4. Tenancy foundation — namespaces, ServiceAccounts, Role/RoleBinding, ResourceQuota/LimitRange (before the app exists)
5. The application — Helm chart, Postgres StatefulSet, external-dns internal name
6. External access — Gateway API + LB Controller
7. Policy + network security — Kyverno + NetworkPolicy, including cross-namespace deny
8. Autoscaling — Karpenter + HPA against real traffic
9. Observability — kube-prometheus-stack, S3-backed Loki, Blackbox Exporter + uptime panel
10. CI/CD — GitHub Actions build/scan/push/deploy-dev/promote-prod pipeline
11. Verification + write-up — end-to-end connectivity proof, final architecture README (the actual interview artifact)

## Honest framing for interviews

This is a deliberately-built learning/portfolio project, not production
experience — no real user traffic, no on-call. Frame it that way
directly rather than implying otherwise; overselling reads worse than
honest framing. Its value is proportional to being able to defend
*any single piece* an interviewer picks at random, not to the number
of technologies listed.
