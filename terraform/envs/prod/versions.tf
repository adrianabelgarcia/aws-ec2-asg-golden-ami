terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # Partial configuration: bucket, key and region come from backend.hcl.
  # Run: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Repository  = "aws-ec2-asg-golden-ami"
      Environment = var.environment
      Service     = var.service_name
      ManagedBy   = "terraform"
    }
  }
}
