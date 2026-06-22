## What was broken and what I changed

- The application listened on `127.0.0.1`, so Kubernetes probes and Service traffic could not reliably reach it through the pod IP. I changed it to bind to `0.0.0.0`, kept `PORT`/`HOST` configurable through environment variables, and verified `/` and `/health` through the final ALB.
- The app kept an unbounded in-memory audit buffer and allocated a 32 MB buffer per `/` request. I removed that unsafe behavior because it was an avoidable memory/DoS risk and not needed for the assignment.
- The Docker/Kubernetes image path used a placeholder and `:latest`. I pushed an immutable ECR image tag and updated the manifest to use `app-8922114-amd64`; the amd64 suffix is intentional because the first image built on Apple Silicon was not pullable by Fargate.
- The original Fargate profile selected the wrong namespace, so the app would not schedule in `nodeapp`. I added explicit Fargate profiles for CoreDNS, the AWS Load Balancer Controller, and the application namespace.
- The AWS Load Balancer Controller IRSA trust relationship referenced the wrong service account. I fixed the trust to `kube-system:aws-load-balancer-controller`, so the controller can assume only its own IAM role.
- Public subnet discovery for the internet-facing ALB was incomplete. I tagged public subnets with `kubernetes.io/role/elb = 1` and private subnets with `kubernetes.io/role/internal-elb = 1`.
- The Ingress was missing `alb.ingress.kubernetes.io/target-type: ip`, which is required for Fargate pod IP targets. I added it and verified the ALB routes to healthy pods.
- The VPC layout was cleaned up into public, private, and database subnet tiers across three AZs. Fargate workloads run in private subnets; the public ALB is the only internet-facing entry point.
- Terraform state was moved to an encrypted S3 backend, and the empty local state file was removed from the repository.
- EKS managed addon versions are pinned instead of using `most_recent`, so future Terraform plans are deterministic and addon upgrades happen intentionally.

## Not implemented / harden next

I asked Vladislav whether to implement the full production platform layer or keep this submission focused; based on his guidance, I implemented what is needed to satisfy the task and documented the remaining production hardening explicitly.

- Add one NAT Gateway per AZ. The current single NAT Gateway is a cost-conscious test choice, but production private egress should not depend on one AZ.
- Move EKS API access to a private-only path or restrict it to stable VPN/office/CI egress CIDRs. For the task it is restricted to my current workstation `/32`.
- Add production observability as a Helmfile-managed platform layer. For logs, I would use the EKS Fargate logging path with Fluent Bit-compatible configuration and ship logs to Elasticsearch, then use Kibana for search and incident investigation. For metrics, I would deploy VictoriaMetrics and scrape Kubernetes, ALB/controller, and application metrics where available. Chart versions and per-environment values would live in the repo so changes are reviewed, reproducible, and promoted consistently.
- Add External Secrets Operator with AWS Secrets Manager or SSM Parameter Store for application secrets, using IRSA as the trust boundary.
- Package application manifests with Helm for multi-environment promotion. I kept plain manifests because the assignment requires `kubectl apply -f k8s/`.
- Add metrics-server and a scaling strategy such as HPA/KEDA if traffic patterns require it.
- Add external-dns if DNS ownership is part of the platform.
- Add NetworkPolicy only with a compatible enforcement layer and a clear traffic matrix; I left default NACLs in place and relied on security groups for this task.
- Add CI/CD to build the correct image platform, scan images, push immutable tags, and deploy through a reviewed promotion flow.
- Add a documented Kubernetes upgrade runbook covering EKS upgrade insights, deprecated APIs, pinned addon upgrades, and workload validation.

## Deployment notes

Terraform state is stored in S3 at `s3://devops-test-tfstate-056300054271/devops-test/terraform.tfstate`.

After `terraform apply`, I built and pushed the application image with an explicit amd64 platform tag because EKS Fargate could not pull the first Apple Silicon image:

```bash
aws ecr get-login-password --region eu-central-1 \
  | docker login --username AWS --password-stdin 056300054271.dkr.ecr.eu-central-1.amazonaws.com

docker buildx build \
  --platform linux/amd64 \
  -t 056300054271.dkr.ecr.eu-central-1.amazonaws.com/devops-test/nodeapp:app-8922114-amd64 \
  --push app

kubectl apply -f k8s/
```

The live ALB endpoint verified during the test was `http://k8s-nodeapp-nodeapp-bc46885b8a-1620956232.eu-central-1.elb.amazonaws.com`; both `/` and `/health` returned HTTP 200.

## Architecture questions

**Subnet layout.** The VPC has public, private, and database subnet tiers across three AZs. Public subnets host internet-facing entry/egress components such as the ALB, Internet Gateway routing, and NAT Gateway. Private subnets host EKS/Fargate workloads so pods do not receive public IPs and are reached only through the ALB or private AWS networking. Database subnets are reserved for future stateful services such as RDS and keep data-layer placement separate from app workloads. For production traffic, I would add one NAT Gateway per AZ and consider private-only EKS API access through VPN/CI/bastion paths.

**NAT placement and availability.** The current design uses a single NAT Gateway in one public subnet, and private subnet route tables send internet-bound egress through it. This is cost-conscious for the test, but the failure mode is that private workloads in multiple AZs depend on one NAT/AZ for egress. If that NAT Gateway or AZ fails, pods may lose outbound access to public endpoints not covered by VPC endpoints. For production I would use one NAT Gateway per AZ and route each private subnet to its local NAT. That costs more hourly and per GB, but removes a single-AZ egress dependency.

**IAM.** The AWS Load Balancer Controller uses IRSA so only its Kubernetes service account gets the AWS permissions needed to create and manage ALBs, listeners, target groups, and security group rules. This is better than using a broad node or pod execution role because the permission boundary is tied to one workload identity. IRSA requires an IAM OIDC provider for the EKS cluster and a role trust policy allowing `sts:AssumeRoleWithWebIdentity`. The trust relationship must match the service account subject, in this case `system:serviceaccount:kube-system:aws-load-balancer-controller`, and audience `sts.amazonaws.com`.

**Subnet discovery.** The AWS Load Balancer Controller discovers candidate subnets from Kubernetes/AWS tags. For an internet-facing ALB, public subnets need `kubernetes.io/role/elb = 1`; private/internal load balancer subnets use `kubernetes.io/role/internal-elb = 1`. If discovery fails, the Ingress will not reconcile into a working ALB, or the controller will emit subnet-related errors. I would debug it by checking Ingress events, controller logs, subnet tags, route tables, and whether the selected subnets span enough AZs. In this deployment, the public subnets are tagged for internet-facing ALB discovery.

**Fargate vs node groups.** Fargate removes node management, patching, and capacity planning for this small stateless service, which is useful for a focused assignment and low-ops workloads. The trade-off is less control over node-level behavior: DaemonSets, privileged agents, custom AMIs, host networking, and some storage patterns are limited or unavailable. Managed node groups are a better fit when workloads need daemon-based observability/security tooling, GPUs, local storage, or tighter cost control at sustained utilization. I would choose Fargate for simple stateless services with bursty or low operational overhead needs, and node groups for platform-heavy or performance-sensitive clusters.

**Secrets.** I would not store database credentials or API keys in the repo or plain Kubernetes manifests. A production approach would be External Secrets Operator backed by AWS Secrets Manager or SSM Parameter Store. The application would receive a Kubernetes Secret generated from the external store, while ESO would use IRSA to read only the specific secret paths it needs. The trust boundary is AWS IAM plus the Kubernetes service account: the app can consume the resulting secret, but it does not need direct AWS permissions to read all secrets. Rotation would happen in the external secrets backend and be synchronized into Kubernetes.

**Cluster upgrades.** I selected Kubernetes 1.30 intentionally because it was the oldest available EKS version in this account, leaving room for reviewers to test one or more minor upgrades against the submitted code. I would upgrade one Kubernetes minor version at a time as a planned Terraform change, not an ad hoc edit. Before applying, I would check EKS upgrade insights, deprecated APIs, AWS Load Balancer Controller compatibility, and target addon versions. Then I would update `cluster_version`, pin compatible addon versions, run `terraform plan/apply`, and validate CoreDNS, VPC CNI, kube-proxy, ALB reconciliation, pod scheduling, and application health to prove the path is clean and repeatable. For stateful workloads, I would first verify backups, storage driver compatibility, PodDisruptionBudgets, and quorum/leader behavior, then upgrade one member at a time.

**Observability and SLOs.** Before declaring this production-ready, I would want application logs, Fargate platform logs, Kubernetes events, ALB metrics, pod readiness/restart visibility, infrastructure metrics, and dashboards for request rate, error rate, latency, and saturation. For logs, I would use the EKS Fargate logging path with Fluent Bit-compatible configuration and ship to Elasticsearch/Kibana or another central log backend. For metrics, I would use VictoriaMetrics or a managed equivalent and include application metrics, ALB/controller metrics, EKS health, NAT Gateway errors/bytes, VPC endpoint health, and AWS service quotas where relevant. One user-facing alert I would add is ALB target 5xx rate above 1% for 5 minutes, because it reflects real request failures. I would also alert if healthy target count drops below 2 for several minutes, and add infrastructure alerts for NAT Gateway packet drops/errors, abnormal data transfer, and sustained pod restarts or pending pods.

## Self-review

I would trust this for a small stateless test service because the app is reachable through an ALB, pods run privately on Fargate, Terraform state is remote, IAM is scoped through IRSA, manifests avoid `latest`, and health checks prove the deployment path works. I would not call it fully production-ready yet because NAT is single-AZ, observability is documented but not implemented, secrets integration is not installed, scaling is not configured, and the app manifests are intentionally plain YAML to satisfy the required `kubectl apply -f k8s/` workflow. After implementing the hardening items above, especially observability/alerting, secrets management, scaling, multi-AZ NAT, CI/CD, and Helm-managed promotion, I would trust it on a production on-call rotation and be comfortable being responsible for it.
