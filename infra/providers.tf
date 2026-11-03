terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "wiz-tfstate-228886155047"
    key            = "wiz/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "wiz-exercise"
      Owner   = "Olivia"
    }
  }
}
