# Patch compliance: patches are measured here and remediated by rebuilding the AMI, never by
# patching instances in place. The maintenance window runs a scan and reports the result.
resource "aws_ssm_patch_baseline" "al2023" {
  name                              = "${var.name}-al2023"
  description                       = "Security and critical fixes for Amazon Linux 2023, approved after 7 days"
  operating_system                  = "AMAZON_LINUX_2023"
  approved_patches_compliance_level = "HIGH"

  approval_rule {
    approve_after_days  = 7
    compliance_level    = "HIGH"
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  tags = local.common_tags
}

resource "aws_ssm_patch_group" "this" {
  baseline_id = aws_ssm_patch_baseline.al2023.id
  patch_group = local.patch_group
}

resource "aws_ssm_maintenance_window" "patch_scan" {
  name                       = "${var.name}-patch-scan"
  description                = "Weekly patch compliance scan for ${var.name}"
  schedule                   = var.patch_schedule
  duration                   = 3
  cutoff                     = 1
  allow_unassociated_targets = false
  tags                       = local.common_tags
}

resource "aws_ssm_maintenance_window_target" "patch_scan" {
  window_id     = aws_ssm_maintenance_window.patch_scan.id
  resource_type = "INSTANCE"
  description   = "Instances in the ${local.patch_group} patch group"

  targets {
    key    = "tag:PatchGroup"
    values = [local.patch_group]
  }
}

data "aws_iam_policy_document" "maintenance_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "maintenance" {
  name               = "${var.name}-maintenance-window"
  assume_role_policy = data.aws_iam_policy_document.maintenance_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "maintenance" {
  role       = aws_iam_role.maintenance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

resource "aws_ssm_maintenance_window_task" "patch_scan" {
  window_id        = aws_ssm_maintenance_window.patch_scan.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance.arn
  max_concurrency  = "25%"
  max_errors       = "10%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.patch_scan.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      service_role_arn = aws_iam_role.maintenance.arn
      timeout_seconds  = 3600

      parameter {
        name   = "Operation"
        values = ["Scan"]
      }
    }
  }
}
