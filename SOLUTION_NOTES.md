# Solution Notes

- Networking is now spread across three AZs, with public subnets for the internet-facing ALB/NAT, private subnets for EKS Fargate pods, and isolated database subnets reserved for future stateful services.
- The submitted design keeps a single NAT gateway to control test cost. Production should use one NAT gateway per AZ to avoid cross-AZ egress dependency and an AZ-local NAT failure taking private egress down.
- Interface VPC endpoints were added for EC2, ECR API, ECR Docker registry, ELBv2, CloudWatch Logs, and STS, plus an S3 gateway endpoint. This reduces NAT dependency and cost for common pod/controller AWS API traffic such as image pulls, token calls, and ALB reconciliation.
- The VPC endpoint security group allows TCP/443 only from the private workload subnet CIDRs; no broad inbound access is needed for endpoint ENIs.
- Default network ACLs are left in place intentionally. Security groups are the primary stateful control plane here; restrictive stateless NACLs are easy to misconfigure for Kubernetes/Fargate ephemeral traffic and are better added only with a clear compliance-driven traffic matrix.
- The EKS public endpoint is restricted to the candidate workstation public IP for this assignment. For production, replace this with stable VPN/office/CI egress CIDRs or run private-only API access through VPN, Direct Connect, or a controlled bastion path.
- The AWS Load Balancer Controller uses the upstream IAM policy. For production, review and trim permissions against the exact ingress features in use.
- The app is kept as plain Kubernetes manifests because the assignment requires `kubectl apply -f k8s/`. For a multi-environment production service, Helm, Kustomize, or a GitOps controller would be a better way to manage environment-specific values and release promotion.
