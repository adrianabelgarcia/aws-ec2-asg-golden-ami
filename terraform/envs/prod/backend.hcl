# Placeholder values. Replace the bucket with the real state bucket before running init.
bucket       = "acme-tfstate-111111111111"
key          = "aws-ec2-asg-golden-ami/prod/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
