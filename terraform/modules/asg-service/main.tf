data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0

  name = local.ami_ssm_parameter_name
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # The pipeline passes ami_id explicitly; otherwise the promoted AMI is read from SSM.
  ami_id = coalesce(var.ami_id, one(data.aws_ssm_parameter.ami[*].value))

  ami_ssm_parameter_name = coalesce(
    var.ami_ssm_parameter_name,
    "/acme-demo/${var.service_name}/${var.environment}/ami-id",
  )

  patch_group = "${var.service_name}-al2023"
  asg_name    = var.name
  hook_name   = "${var.name}-terminate-drain"
  alb_name    = "${substr(var.name, 0, 24)}-alb"
  tg_name     = "${substr(var.name, 0, 25)}-tg"

  common_tags = merge(var.tags, {
    Service     = var.service_name
    Environment = var.environment
    Module      = "asg-service"
  })
}
