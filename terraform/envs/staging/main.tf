locals {
  name     = "${var.service_name}-${var.environment}"
  vpc_cidr = "10.20.0.0/16"
  azs      = var.availability_zones
}

# Network: three AZs, private subnets for the fleet, public subnets for the ALB only.
# Flow logs are on in every environment.
module "vpc" {
  #checkov:skip=CKV_TF_1: Registry module pinned by an exact-minor version constraint (~> 6.7) and locked in .terraform.lock.hcl; commit-hash pinning applies to git sources only.
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  private_subnets = [for i in range(3) : cidrsubnet(local.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(local.vpc_cidr, 8, 200 + i)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames           = true
  enable_dns_support             = true
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 30
  flow_log_max_aggregation_interval               = 60
}

module "service" {
  source = "../../modules/asg-service"

  name               = local.name
  service_name       = var.service_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets
  certificate_arn    = var.certificate_arn
  ami_id             = var.ami_id

  # Capacity: mostly Spot, cheap and disposable
  min_size                        = 2
  max_size                        = 4
  desired_capacity                = 2
  on_demand_base_capacity         = 0
  on_demand_percentage_above_base = 20
  instance_types                  = ["m7i.large", "m6i.large", "m7a.large", "m6a.large"]

  deletion_protection   = false
  alarm_email_endpoints = var.alarm_email_endpoints

  warm_pool = {
    enabled                     = false
    pool_state                  = "Stopped"
    min_size                    = 0
    max_group_prepared_capacity = 2
  }

  enable_backup = false

  # Staging builds the golden AMI; prod copies it into its own account.
  ami_consumer_account_ids = var.ami_consumer_account_ids

  # Staging keeps the schedule empty on purpose; prod shows the pattern.
  scheduled_actions = {}
}
