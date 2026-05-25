module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # Fargate-only cluster. We declare profiles for kube-system (CoreDNS / metrics)
  # and for our workloads.
  fargate_profiles = {
    # CoreDNS must run on Fargate too — there are no EC2 nodes in this cluster.
    kube_system = {
      name = "kube-system"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            "k8s-app" = "kube-dns"
          }
        }
      ]
      subnet_ids = aws_subnet.public_data[*].id
    }

    # Workload Fargate profile.
    apps = {
      name = "apps"
      selectors = [
        {
          namespace = "default"
        }
      ]
      subnet_ids = aws_subnet.public_data[*].id
    }
  }

  # Cluster add-ons. CoreDNS is patched to run on Fargate via the compute config.
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate"
        resources = {
          limits   = { cpu = "0.25", memory = "256M" }
          requests = { cpu = "0.25", memory = "256M" }
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # Give the operator running `terraform apply` cluster-admin so kubeconfig works
  # immediately. In real production you would use access entries with least
  # privilege and SSO.
  enable_cluster_creator_admin_permissions = true

  tags = {
    Project = var.project
  }
}
