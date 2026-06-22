module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = ["46.49.73.198/32"]

  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Fargate-only cluster. CoreDNS, the AWS Load Balancer Controller, and the
  # application all need matching profiles because there are no EC2 nodes.
  fargate_profiles = {
    coredns = {
      name = "coredns"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            "k8s-app" = "kube-dns"
          }
        }
      ]
      subnet_ids = module.vpc.private_subnets
    }

    alb_controller = {
      name = "alb-controller"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            "app.kubernetes.io/name" = "aws-load-balancer-controller"
          }
        }
      ]
      subnet_ids = module.vpc.private_subnets
    }

    apps = {
      name = "apps"
      selectors = [
        {
          namespace = var.app_namespace
        }
      ]
      subnet_ids = module.vpc.private_subnets
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
