# Golden AMI for the sample-app service.
#
# Builds an Amazon Linux 2023 image with OS hardening, the CloudWatch agent, the application
# installed as a systemd unit, and a Trivy vulnerability gate. The build instance is reached
# over AWS Systems Manager Session Manager, so no SSH key pair is ever left in the image.

packer {
  required_version = ">= 1.11.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.8"
    }
  }
}

locals {
  build_timestamp = formatdate("YYYYMMDDHHmmss", timestamp())
  build_date      = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timestamp())
  ami_name        = "${var.service_name}-${var.git_sha}-${local.build_timestamp}"
}

source "amazon-ebs" "al2023" {
  region        = var.region
  instance_type = var.build_instance_type

  ami_name        = local.ami_name
  ami_users       = var.ami_users
  ami_description = "Golden AMI for ${var.service_name} at ${var.git_sha}. Built by Packer, scanned by Trivy."

  # Amazon Linux 2023, latest x86_64 HVM image published by Amazon.
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }
    most_recent = true
    owners      = ["amazon"]
  }

  # IMDSv2 is enforced on the build instance too, so the image is never built with IMDSv1 enabled.
  imds_support = "v2.0"

  # Session Manager transport: no inbound port 22, no security group rule, no key pair kept.
  communicator            = "ssh"
  ssh_username            = "ec2-user"
  ssh_interface           = "session_manager"
  temporary_key_pair_type = "ed25519"
  ssh_timeout             = "15m"

  # Temporary instance profile for the build only, scoped to the SSM channel actions.
  temporary_iam_instance_profile_policy_document {
    Statement {
      Sid    = "SessionManagerChannel"
      Effect = "Allow"
      Action = [
        "ssm:DescribeAssociation",
        "ssm:GetDeployablePatchSnapshotForInstance",
        "ssm:GetDocument",
        "ssm:DescribeDocument",
        "ssm:GetManifest",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:ListAssociations",
        "ssm:ListInstanceAssociations",
        "ssm:PutInventory",
        "ssm:PutComplianceItems",
        "ssm:PutConfigurePackageResult",
        "ssm:UpdateAssociationStatus",
        "ssm:UpdateInstanceAssociationStatus",
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
        "ec2messages:AcknowledgeMessage",
        "ec2messages:DeleteMessage",
        "ec2messages:FailMessage",
        "ec2messages:GetEndpoint",
        "ec2messages:GetMessages",
        "ec2messages:SendReply",
      ]
      Resource = ["*"]
    }
    Version = "2012-10-17"
  }

  # Encrypted root volume with a customer managed KMS key (shared by the AMI and its snapshot).
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = var.kms_key_id
    delete_on_termination = true
  }
  encrypt_boot = true
  kms_key_id   = var.kms_key_id

  run_tags = {
    Name      = "packer-build-${var.service_name}"
    ManagedBy = "packer"
    Purpose   = "golden-ami-build"
  }

  tags = {
    Name      = local.ami_name
    Service   = var.service_name
    Release   = var.git_sha
    GitSha    = var.git_sha
    BuildDate = local.build_date
    BaseAmi   = "{{ .SourceAMI }}"
    ScanTool  = "trivy-${var.trivy_version}"
    ManagedBy = "packer"
  }

  snapshot_tags = {
    Name      = local.ami_name
    Release   = var.git_sha
    ManagedBy = "packer"
  }
}

build {
  name    = "golden-ami"
  sources = ["source.amazon-ebs.al2023"]

  # Stage every file asset once, then run the provisioning scripts in order.
  provisioner "file" {
    source      = "../app/bin/sample-app"
    destination = "/tmp/sample-app"
  }

  provisioner "file" {
    source      = "files/"
    destination = "/tmp/golden/"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    environment_vars = [
      "AWS_REGION=${var.region}",
      "GOLDEN_FILES=/tmp/golden",
      "APP_BINARY=/tmp/sample-app",
      "GIT_SHA=${var.git_sha}",
    ]
    scripts = ["scripts/10-system-baseline.sh"]
  }

  # Kernel and systemd updates only take effect after a reboot, so reboot and continue.
  provisioner "shell" {
    execute_command   = "sudo -E bash '{{ .Path }}'"
    expect_disconnect = true
    inline            = ["systemctl reboot"]
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    pause_before    = "60s"
    environment_vars = [
      "AWS_REGION=${var.region}",
      "GOLDEN_FILES=/tmp/golden",
      "APP_BINARY=/tmp/sample-app",
      "GIT_SHA=${var.git_sha}",
      "BUILD_DATE=${local.build_date}",
      "TRIVY_VERSION=${var.trivy_version}",
      "TRIVY_SHA256=${var.trivy_sha256}",
    ]
    scripts = [
      "scripts/20-hardening.sh",
      "scripts/30-observability.sh",
      "scripts/40-application.sh",
      "scripts/50-vulnerability-scan.sh",
      "scripts/90-finalize.sh",
    ]
  }

  # Scan report leaves the build instance so CI can archive it next to the AMI.
  provisioner "file" {
    direction   = "download"
    source      = "/var/tmp/trivy-report.json"
    destination = "reports/trivy-${var.git_sha}.json"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
    custom_data = {
      service    = var.service_name
      git_sha    = var.git_sha
      build_date = local.build_date
    }
  }
}
