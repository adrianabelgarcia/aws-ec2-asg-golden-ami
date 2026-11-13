# Optional. The fleet is stateless, so this is for the EBS volumes of stateful side workloads
# that opt in with the tag Backup=daily (set on volumes by the launch template).
resource "aws_backup_vault" "this" {
  count = var.enable_backup ? 1 : 0

  name        = "${var.name}-vault"
  kms_key_arn = aws_kms_key.this.arn
  tags        = local.common_tags
}

resource "aws_backup_plan" "this" {
  count = var.enable_backup ? 1 : 0

  name = "${var.name}-daily"

  rule {
    rule_name         = "daily-35d"
    target_vault_name = aws_backup_vault.this[0].name
    schedule          = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  tags = local.common_tags
}

data "aws_iam_policy_document" "backup_assume" {
  count = var.enable_backup ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  count = var.enable_backup ? 1 : 0

  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume[0].json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  count = var.enable_backup ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "this" {
  count = var.enable_backup ? 1 : 0

  name         = "${var.name}-tagged-volumes"
  plan_id      = aws_backup_plan.this[0].id
  iam_role_arn = aws_iam_role.backup[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "daily"
  }
}
