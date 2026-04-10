terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  # State stored locally in infra/terraform.tfstate
  # (add to .gitignore — contains resource IDs but no secrets)
  backend "local" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "NightlyJobs"
      ManagedBy = "Terraform"
    }
  }
}

# Reuse the default VPC and a public subnet — keeps networking zero-config
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Ubuntu 24.04 LTS AMI (arm64 for cost savings on t4g, x86 for t3)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}