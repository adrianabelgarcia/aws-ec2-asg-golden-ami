variable "name" {
  type        = string
  description = "Resource name prefix, usually '<service>-<environment>'. Must be 3-24 chars because ALB and target group names are derived from it."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.name))
    error_message = "name must be 3-24 chars: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "service_name" {
  type        = string
  description = "Logical service name. Used in SSM parameter paths and tags."
  default     = "sample-app"
}

variable "environment" {
  type        = string
  description = "Deployment environment. Controls defaults only; behavior is set explicitly through variables."

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either staging or prod."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC that hosts the load balancer, the instances and the security groups."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnets for the internet-facing ALB. At least two AZs are required."

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least two public subnets in different AZs are required for the ALB."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for the instances. Three AZs are expected in every environment."

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnets are required; three is the standard."
  }
}

variable "certificate_arn" {
  type        = string
  description = "ARN of the ACM certificate served by the HTTPS listener."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "ami_id" {
  type        = string
  description = "Golden AMI to launch. Passed by the release pipeline. When null the AMI ID is read from ami_ssm_parameter_name, which keeps plan and apply from unrelated workflows on the same version."
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be null or an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "ami_ssm_parameter_name" {
  type        = string
  description = "SSM parameter holding the currently promoted AMI ID. Written by the release pipeline, read here when ami_id is null."
  default     = null
}

variable "app_port" {
  type        = number
  description = "Port the application listens on. Instances accept traffic on this port from the ALB only."
  default     = 8080

  validation {
    condition     = var.app_port >= 1024 && var.app_port <= 65535
    error_message = "app_port must be between 1024 and 65535."
  }
}

variable "health_check_path" {
  type        = string
  description = "HTTP path the ALB uses for target health. Must return 200 when healthy and 503 while draining."
  default     = "/health"
}

variable "instance_types" {
  type        = list(string)
  description = "Instance types for the mixed instances policy. Several same-size families widen the Spot pool."
  default     = ["m7i.large", "m6i.large", "m7a.large", "m6a.large"]

  validation {
    condition     = length(var.instance_types) >= 1
    error_message = "At least one instance type is required."
  }
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances."
  default     = 2
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances."
  default     = 6
}

variable "desired_capacity" {
  type        = number
  description = "Initial desired capacity. Target tracking owns the value after creation, so changes to it are ignored."
  default     = 2
}

variable "on_demand_base_capacity" {
  type        = number
  description = "Number of on-demand instances that are always kept in the group."
  default     = 0
}

variable "on_demand_percentage_above_base" {
  type        = number
  description = "Percentage of on-demand capacity above the base. The remainder is Spot."
  default     = 100

  validation {
    condition     = var.on_demand_percentage_above_base >= 0 && var.on_demand_percentage_above_base <= 100
    error_message = "on_demand_percentage_above_base must be between 0 and 100."
  }
}

variable "root_volume_gb" {
  type        = number
  description = "Root EBS volume size in GiB. The volume is encrypted with the module KMS key."
  default     = 20
}

variable "health_check_grace_period" {
  type        = number
  description = "Seconds after launch before ELB health checks count against an instance."
  default     = 120
}

variable "instance_warmup_seconds" {
  type        = number
  description = "Seconds an instance is given to warm up before it counts toward scaling and instance refresh health."
  default     = 120
}

variable "deregistration_delay" {
  type        = number
  description = "Seconds the ALB waits for in-flight requests before finishing deregistration. Must cover the app drain delay."
  default     = 30
}

variable "lifecycle_drain_timeout" {
  type        = number
  description = "Seconds the ASG waits for the instance to finish draining before it proceeds with termination anyway."
  default     = 300
}

variable "refresh_min_healthy_percentage" {
  type        = number
  description = "Minimum percentage of the group that must stay healthy during an instance refresh."
  default     = 90

  validation {
    condition     = var.refresh_min_healthy_percentage >= 50 && var.refresh_min_healthy_percentage <= 100
    error_message = "refresh_min_healthy_percentage must be between 50 and 100."
  }
}

variable "refresh_checkpoint_percentages" {
  type        = list(number)
  description = "Progress points at which the refresh pauses so a human or the alarms can check the new version."
  default     = [50]
}

variable "refresh_checkpoint_delay" {
  type        = number
  description = "Seconds the refresh pauses at each checkpoint."
  default     = 600
}

variable "refresh_auto_rollback" {
  type        = bool
  description = "Roll the group back to the previous launch template version when a rollback alarm fires during an instance refresh."
  default     = true
}

variable "warm_pool" {
  type = object({
    enabled                     = bool
    pool_state                  = optional(string, "Stopped")
    min_size                    = optional(number, 0)
    max_group_prepared_capacity = optional(number, 2)
  })
  description = "Optional warm pool of pre-initialized instances, which shortens scale-out and refresh time."
  default     = { enabled = false }

  validation {
    condition     = contains(["Stopped", "Running", "Hibernated"], var.warm_pool.pool_state)
    error_message = "warm_pool.pool_state must be Stopped, Running or Hibernated."
  }
}

variable "cpu_target_percent" {
  type        = number
  description = "Target average CPU utilization for the CPU target tracking policy."
  default     = 60
}

variable "requests_per_target" {
  type        = number
  description = "Target ALB requests per target for the request-count target tracking policy."
  default     = 500
}

variable "scheduled_actions" {
  type = map(object({
    recurrence       = string
    min_size         = optional(number, -1)
    max_size         = optional(number, -1)
    desired_capacity = optional(number, -1)
    time_zone        = optional(string, "UTC")
  }))
  description = "Scheduled scaling actions keyed by name. -1 means leave the value unchanged."
  default     = {}
}

variable "rollback_5xx_percent" {
  type        = number
  description = "Percentage of requests answered with a target 5xx that triggers an automatic rollback during an instance refresh."
  default     = 5
}

variable "rollback_p95_latency_seconds" {
  type        = number
  description = "p95 target response time in seconds that triggers an automatic rollback during an instance refresh."
  default     = 1
}

variable "rate_limit_per_5min" {
  type        = number
  description = "Requests per source IP in any 5-minute window before the WAF rate rule blocks it."
  default     = 2000
}

variable "deletion_protection" {
  type        = bool
  description = "Protect the ALB from accidental deletion."
  default     = true
}

variable "alb_log_retention_days" {
  type        = number
  description = "Days to keep ALB access logs in S3."
  default     = 90
}

variable "app_log_group_name" {
  type        = string
  description = "CloudWatch Logs group for application and audit logs. Must match the agent configuration baked into the AMI."
  default     = "/acme-demo/sample-app/app"
}

variable "log_retention_days" {
  type        = number
  description = "Retention in days for application and WAF log groups. Defaults to one year to keep an audit trail."
  default     = 365
}

variable "app_s3_read_arns" {
  type        = list(string)
  description = "S3 object ARNs (with wildcards allowed) the application may read, for example a config prefix. Empty grants no S3 access."
  default     = []
}

variable "alarm_email_endpoints" {
  type        = list(string)
  description = "Email addresses subscribed to the alerts SNS topic. Each address must confirm the subscription."
  default     = []
}

variable "patch_schedule" {
  type        = string
  description = "Cron expression for the SSM patch compliance scan window (UTC)."
  default     = "cron(0 3 ? * SUN *)"
}

variable "enable_backup" {
  type        = bool
  description = "Create an AWS Backup plan for volumes tagged Backup=daily. Off by default because the fleet is stateless."
  default     = false
}

variable "backup_retention_days" {
  type        = number
  description = "Days to keep AWS Backup recovery points."
  default     = 35
}

variable "tags" {
  type        = map(string)
  description = "Extra tags applied to every resource in the module that supports tags."
  default     = {}
}

variable "ami_consumer_account_ids" {
  type        = list(string)
  description = "Accounts allowed to decrypt this key so they can copy the golden AMI into their own account (cross-account promotion)."
  default     = []

  validation {
    condition     = alltrue([for id in var.ami_consumer_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Every ami_consumer_account_ids entry must be a 12-digit AWS account ID."
  }
}
