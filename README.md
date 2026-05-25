# DevOps / SRE Qualification Task — Production EKS Fargate Deployment

**Time budget:** up to 4 hours of focused work.
**Cloud:** AWS (use a sandbox or your own account — we will reimburse documented charges).
**Region:** `eu-central-1` (adjust `terraform/variables.tf` if you prefer another).

---

## How to approach this

**This is a qualification task, not a sandbox exercise.** Treat every file in this repository as code you are about to merge into a mature production environment that your team is on-call for. The bar is not "did it eventually return 200." The bar is: *would you sign off on this in a real change-review, with real PagerDuty consequences, on a Friday afternoon?*

Before you submit, review your own work the way a senior on the team would. If something works but you wouldn't want it on the on-call rotation as written, fix it or call it out. We will read your repository, your Terraform state, and your `SOLUTION.md` with the same lens.

Concretely, the gold rule we evaluate against:

> Anything you ship should be something you would defend, unprompted, in a production post-incident review.

That means: idempotent IaC, least-privilege IAM, healthy probes, sane image tagging, no manual cluster-side patches that aren't reflected in code, no `:latest` in production manifests, no secrets in the repo, no "I'll fix it later" left in `main`. If you knowingly cut a corner, say so in `SOLUTION.md` and explain the trade-off.

---

## Goal

This repository contains a small Node.js HTTP service together with Terraform and Kubernetes manifests intended to deploy it to a production-grade Amazon EKS cluster using **Fargate** for compute and an **Application Load Balancer** (ALB) for ingress.

The repository is **not** in a working state. Several things will prevent the application from being reachable end-to-end — some are hard failures the next `terraform apply` or pod will show you, some are silent and only surface during code review. Your task is to take this repository as it is, make whatever changes are needed, and deliver a deployed, internet-reachable service that meets the gold rule above.

How many things are wrong, where they live, and what kind they are (Terraform, Kubernetes, application, architectural) is part of the assessment. We deliberately do not tell you. This mirrors the kind of incident-response and code-review work you would do on the team from week one.

---

## What you must deliver

1. **A running EKS cluster** provisioned by `terraform apply`, including:
   - A dedicated VPC with public and private subnets across ≥ 2 availability zones, NAT, and an Internet Gateway.
   - An EKS cluster running Fargate compute only (no managed node groups).
   - AWS Load Balancer Controller installed and healthy.
   - The Node.js application running on Fargate, exposed via an ALB created from a Kubernetes `Ingress`.
2. **A public ALB URL** that returns `HTTP 200` on `/` and `/health`.
3. **The Terraform state** — share it with us so we can inspect it. Either:
   - configure an S3 backend (preferred), and give us read access to the state bucket / key, **or**
   - if you used local state, attach `terraform.tfstate` along with the `terraform output` to your submission.
4. **`SOLUTION.md`** (≤ 2 pages) covering:
   - What you found broken and how you fixed each item — keep it as a short, scannable list. We don't expect a literary essay.
   - Anything you noticed but chose not to fix, and why (out of scope, out of time, out of risk appetite). Be explicit — silent corner-cutting is the failure mode we filter for.
   - Your answers to the architecture questions below.
   - A short **self-review against the gold rule**: walk us through which parts of your submission you would defend in a real production post-incident review, and which parts you would flag as known debt.
   - What you would harden next if this were going to production for real.

You do **not** need to destroy the infrastructure when finished — we will tear down after the review. Please leave the cluster running and share `terraform output` and the ALB URL when you submit.

---

## Repository layout

```
.
├── README.md                 # this file
├── terraform/
│   ├── versions.tf
│   ├── variables.tf
│   ├── vpc.tf
│   ├── eks.tf
│   ├── alb-controller.tf
│   ├── ecr.tf
│   └── outputs.tf
├── app/
│   ├── server.js             # Express service: GET / and GET /health
│   ├── package.json
│   └── Dockerfile
└── k8s/
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

---

## Prerequisites

- Terraform ≥ 1.6
- AWS CLI v2, with credentials authorised to create VPC, EKS, IAM, and ECR resources
- `kubectl` ≥ 1.30
- `helm` ≥ 3.13
- Docker (for building and pushing the application image)

---

## Suggested workflow

1. Read `terraform/`, `k8s/`, and `app/` end-to-end before running anything. A few minutes of reading saves a lot of plan-apply churn.
2. `cd terraform && terraform init && terraform apply`. An EKS cluster takes roughly 15–20 minutes to come up; use that time to read the rest of the repo.
3. Configure `kubectl` to talk to the new cluster.
4. Build and push the application image to the ECR repository created by Terraform, then deploy the Kubernetes manifests.
5. Verify the public URL responds. If it doesn't, work back from the failing layer.

How you debug is up to you. We are interested in your reasoning and the changes you ship, not in any particular sequence of commands.

---

## Architecture questions to answer in `SOLUTION.md`

Write a short paragraph (3–6 sentences) on each. We are looking for the depth of your thinking more than the length of your answer.

1. **Subnet layout.** What is the role of each subnet group in this VPC, and why does that separation matter? What would you change in the layout if this were going to production traffic?
2. **NAT placement and availability.** Where does the NAT gateway sit in the current design, and what is the failure mode? How would you change this for production, and what is the cost / availability trade-off?
3. **IAM.** Why does the AWS Load Balancer Controller use IAM Roles for Service Accounts (IRSA) instead of the node / task IAM role? What is the trust relationship that has to be in place for IRSA to work at all?
4. **Subnet discovery.** How does the AWS Load Balancer Controller decide which subnets to put an internet-facing ALB in? What happens if that discovery fails, and how would you debug it?
5. **Fargate vs node groups.** Name two real trade-offs of running this workload on Fargate instead of an EKS managed node group. When would you reach for one over the other?
6. **Secrets.** How would you supply database credentials or third-party API keys to this application in production? Reference at least one concrete mechanism and explain the trust boundary.
7. **Cluster upgrades.** How would you upgrade this cluster to a new Kubernetes minor version without downtime? What changes in your approach if the workload were stateful?
8. **Observability and SLOs.** What's the minimum observability surface you would want before declaring this service production-ready? Pick one metric you would alert on and explain the threshold.

---

## Ground rules

- Use whatever documentation, AWS docs, Stack Overflow, or AI assistants you would use on the job. We care about how you reason and what you ship, not whether you memorised annotation names.
- You may change **anything** in this repository — add files, delete files, rewrite the Node.js app, swap modules. The only constraint is that the final state must deploy via `terraform apply` + `kubectl apply -f k8s/` (plus a documented image build / push step).
- Do **not** post this repository publicly until after the interview.
- If you get stuck for more than ~30 minutes on any single thing, write down what you tried and move on. We will discuss it in the follow-up call. Honest debugging under uncertainty is more valuable to us than a perfect green ALB.
- A green ALB on its own is not a passing submission. We will read your code with the gold rule in mind: would we trust this on the production on-call rotation as written?

---

## What we evaluate

| Area | What we look for |
|------|------------------|
| AWS networking | VPC layout, subnet roles, route-table reasoning, choice of public vs private placement |
| EKS | Cluster topology, addon configuration, control-plane vs data-plane separation, scheduling behaviour |
| IAM & security | Least-privilege thinking, IRSA / trust policies, secret handling, defence in depth |
| Terraform | Idempotency, module choice, no hard-coded ARNs, clean plans, sensible variables |
| Kubernetes | Manifest correctness, probes, namespaces, ingress configuration, security context |
| Application | Container portability, configuration via env, healthchecks, image hygiene |
| Debugging | How you isolate cause from symptom; how you read logs, events, and AWS responses |
| Architectural judgement | Quality of answers to the architecture questions above; what you flag as smells even if you don't fix them |
| Communication | Clarity of `SOLUTION.md`, honesty about trade-offs and what was skipped |

Good luck. Treat this like the first production system you own on the team — that is what we are hiring for.
