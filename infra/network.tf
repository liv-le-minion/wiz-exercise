data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]    # MongoDB VM
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]  # EKS cluster

  enable_nat_gateway   = true
  single_nat_gateway   = true   # one NAT to save cost
  enable_dns_hostnames = true
  enable_dns_support   = true

  map_public_ip_on_launch = true  # VM in public subnet gets a public IP

  # Tags so the AWS Load Balancer Controller knows where to put the ALB
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
