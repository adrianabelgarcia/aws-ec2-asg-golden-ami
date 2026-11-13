output "alb_dns_name" {
  description = "DNS name of the public ALB. Point the service domain at it with an ALIAS record."
  value       = module.service.alb_dns_name
}

output "asg_name" {
  description = "Auto Scaling group name, used by the release pipeline to watch instance refresh."
  value       = module.service.asg_name
}

output "kms_key_alias" {
  description = "KMS alias the Packer build encrypts the AMI with."
  value       = module.service.kms_key_alias
}

output "ami_ssm_parameter_name" {
  description = "SSM parameter the release pipeline writes the promoted AMI ID to."
  value       = module.service.ami_ssm_parameter_name
}

output "rollback_alarm_names" {
  description = "Alarms that trigger automatic rollback during instance refresh."
  value       = module.service.rollback_alarm_names
}

output "vpc_id" {
  description = "VPC ID of the environment."
  value       = module.vpc.vpc_id
}
