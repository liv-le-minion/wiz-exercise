module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${var.project}-eks"
  kubernetes_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes in PRIVATE subnets

  # API endpoint reachable from your Mac for kubectl
  endpoint_public_access = true

  # Admin pinned to Olivia's user so CI runs don't swap it to the pipeline role
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    cluster_creator = {
      principal_arn = var.admin_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
  kms_key_administrators = [var.admin_arn, aws_iam_role.github_actions.arn]

  # Control plane audit logging -> CloudWatch (used in Step 13)
  enabled_log_types = ["api", "audit", "authenticator"]

  addons = {
    vpc-cni                = { before_compute = true, addon_version = "v1.23.2-eksbuild.10" }
    eks-pod-identity-agent = { before_compute = true, addon_version = "v1.4.1-eksbuild.3" }
    kube-proxy             = { addon_version = "v1.34.6-eksbuild.64" }
    coredns                = { addon_version = "v1.13.2-eksbuild.75" }
  }

  eks_managed_node_groups = {
    default = {
      ami_type                       = "AL2023_x86_64_STANDARD"
      ami_release_version            = "1.34.12-20261031"
      use_latest_ami_release_version = false
      instance_types                 = ["t3.medium"]
      min_size                       = 2
      max_size                       = 3
      desired_size                   = 2
    }
  }
}

# ---------- IAM for the AWS Load Balancer Controller (EKS Pod Identity) ----------
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.project}-alb-controller"
  policy = file("${path.module}/alb-controller-iam-policy.json")
}

resource "aws_iam_role" "alb_controller" {
  name = "${var.project}-alb-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn
}
