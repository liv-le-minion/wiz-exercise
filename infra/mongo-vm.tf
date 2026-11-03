# ---------- Passwords (generated, stored in TF state) ----------
resource "random_password" "mongo_admin" {
  length  = 20
  special = false
}

resource "random_password" "mongo_app" {
  length  = 20
  special = false
}

# ---------- INTENTIONAL: outdated Linux - Ubuntu 20.04 ----------
data "aws_ami" "ubuntu_focal" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# ---------- SSH key ----------
resource "aws_key_pair" "mongo" {
  key_name   = "${var.project}-mongo-key"
  public_key = file(pathexpand("~/.ssh/wiz-mongo.pub"))
}

# ---------- Security group ----------
resource "aws_security_group" "mongo" {
  name        = "${var.project}-mongo-sg"
  description = "MongoDB VM"
  vpc_id      = module.vpc.vpc_id

  # INTENTIONAL: SSH open to the whole internet
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MongoDB only from the K8s private subnets
  ingress {
    description = "MongoDB from K8s private subnets only"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- IAM role for the VM ----------
resource "aws_iam_role" "mongo" {
  name = "${var.project}-mongo-vm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# INTENTIONAL: overly permissive - VM can create/delete any EC2 resources
resource "aws_iam_role_policy_attachment" "mongo_ec2_full" {
  role       = aws_iam_role.mongo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# INTENTIONAL: full S3 access (used for backups, but far broader than needed)
resource "aws_iam_role_policy_attachment" "mongo_s3_full" {
  role       = aws_iam_role.mongo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Fallback access via SSM Session Manager
resource "aws_iam_role_policy_attachment" "mongo_ssm" {
  role       = aws_iam_role.mongo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "mongo" {
  name = "${var.project}-mongo-vm-profile"
  role = aws_iam_role.mongo.name
}

# ---------- The VM (public subnet) ----------
resource "aws_instance" "mongo" {
  ami                         = data.aws_ami.ubuntu_focal.id
  instance_type               = "t3.small"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.mongo.id]
  key_name                    = aws_key_pair.mongo.key_name
  iam_instance_profile        = aws_iam_instance_profile.mongo.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/mongo-userdata.sh", {
    admin_pw = random_password.mongo_admin.result
    app_pw   = random_password.mongo_app.result
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-mongo-vm" }
}
