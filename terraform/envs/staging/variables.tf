variable "region" {
  type        = string
  description = "AWS region for every resource in this environment."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name. Drives resource names and the AMI SSM parameter path."
  default     = "staging"

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "service_name" {
  type        = string
  description = "Service name shared with the AMI build (see packer/variables.pkr.hcl)."
  default     = "sample-app"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the service domain. Must be in the same region as the ALB."
}

variable "ami_id" {
  type        = string
  description = "Golden AMI to deploy. Set by the release pipeline with -var. When null the promoted AMI is read from SSM."
  default     = null
}

variable "alarm_email_endpoints" {
  type        = list(string)
  description = "Email addresses subscribed to the alerts topic."
  default     = []
}

variable "availability_zones" {
  type        = list(string)
  description = "Three availability zone names for the VPC. Pinned explicitly so the layout never shifts when AWS adds a zone."
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "availability_zones must contain exactly three zones."
  }
}

variable "ami_consumer_account_ids" {
  type        = list(string)
  description = "Production account IDs allowed to copy the golden AMI out of this account."
  default     = []
}
