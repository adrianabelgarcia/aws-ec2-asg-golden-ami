variable "region" {
  type        = string
  description = "AWS region where the golden AMI is built and registered."
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "Region must look like an AWS region, for example us-east-1."
  }
}

variable "service_name" {
  type        = string
  description = "Short service identifier. Used in the AMI name and the Service and PatchGroup tags."
  default     = "sample-app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.service_name))
    error_message = "Service_name must be 3-32 chars: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "git_sha" {
  type        = string
  description = "Git commit SHA of the application and provisioning code. Stamped on the AMI as Release and GitSha."

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.git_sha))
    error_message = "Git_sha must be a lowercase hexadecimal commit SHA (7-40 chars)."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID, alias or ARN used to encrypt the build volume and the resulting AMI snapshot. Customer managed key required."

  validation {
    condition     = length(var.kms_key_id) > 0
    error_message = "Kms_key_id is required; the golden AMI must be encrypted with a customer managed key."
  }
}

variable "build_instance_type" {
  type        = string
  description = "Instance type of the temporary build instance. Only build time is affected, not the runtime fleet."
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root volume size in GiB for the golden AMI."
  default     = 20

  validation {
    condition     = var.root_volume_size_gb >= 20 && var.root_volume_size_gb <= 100
    error_message = "Root_volume_size_gb must be between 20 and 100."
  }
}

variable "trivy_version" {
  type        = string
  description = "Trivy release used by the vulnerability gate. Bump together with trivy_sha256."
  default     = "0.76.2"
}

variable "trivy_sha256" {
  type        = string
  description = "SHA-256 of the Trivy x86_64 RPM for trivy_version, taken from the upstream checksums file. The build fails on mismatch."
  default     = "0adb8681adba00c6207fcfa2066464837b46075bf26ace33f6026fe14f583c1c"

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.trivy_sha256))
    error_message = "Trivy_sha256 must be a 64-character lowercase hex SHA-256."
  }
}

variable "ami_users" {
  type        = list(string)
  description = "AWS account IDs that receive launch permission on the AMI and its snapshot. Used to share the staging AMI with the production account before it is copied there."
  default     = []

  validation {
    condition     = alltrue([for id in var.ami_users : can(regex("^[0-9]{12}$", id))])
    error_message = "Every ami_users entry must be a 12-digit AWS account ID."
  }
}
