output "alb_dns_name" {
  description = "DNS name of the public ALB. Point the service domain at it with an ALIAS record."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB, needed for ALIAS records."
  value       = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB, used by dashboards and metric queries."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn" {
  description = "ARN of the application target group."
  value       = aws_lb_target_group.app.arn
}

output "asg_name" {
  description = "Name of the Auto Scaling group. Used by the release pipeline to watch instance refresh."
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling group."
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest version number of the launch template. Changes on every AMI or user data change."
  value       = aws_launch_template.this.latest_version
}

output "instance_security_group_id" {
  description = "Security group attached to the instances."
  value       = aws_security_group.instance.id
}

output "instance_role_arn" {
  description = "IAM role assumed by the instances."
  value       = aws_iam_role.instance.arn
}

output "kms_key_arn" {
  description = "ARN of the customer managed key used for EBS, logs and alerts."
  value       = aws_kms_key.this.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key. The Packer build uses this alias so the AMI and the fleet share one key."
  value       = aws_kms_alias.this.name
}

output "log_group_name" {
  description = "CloudWatch Logs group receiving application and audit logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "alerts_topic_arn" {
  description = "SNS topic receiving alarm notifications."
  value       = aws_sns_topic.alerts.arn
}

output "rollback_alarm_names" {
  description = "Alarms that trigger an automatic rollback during an instance refresh."
  value       = [aws_cloudwatch_metric_alarm.rollback_5xx.alarm_name, aws_cloudwatch_metric_alarm.rollback_latency.alarm_name]
}

output "ami_ssm_parameter_name" {
  description = "SSM parameter the release pipeline writes the promoted AMI ID to."
  value       = local.ami_ssm_parameter_name
}
