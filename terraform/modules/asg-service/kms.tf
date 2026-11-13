# One customer managed key per environment encrypts EBS roots, the log group and the alert topic.
# The golden AMI build references this key through the alias below, so both use the same key.
data "aws_iam_policy_document" "kms" {
  # KMS key policies can only scope resources to "*", which means "this key". The statements are
  # limited by principal and by conditions instead.
  #checkov:skip=CKV_AWS_109: Account root administration of the key is the standard KMS key policy; IAM delegation controls who can use it.
  #checkov:skip=CKV_AWS_111: The write actions are limited to named service roles and the CloudWatch Logs service principal with conditions.
  #checkov:skip=CKV_AWS_356: resource "*" in a key policy refers to this key only.

  statement {
    sid       = "AccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # Auto Scaling launches encrypted EBS volumes through its service-linked role.
  statement {
    sid    = "AutoScalingEncryptedVolumes"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }

  statement {
    sid       = "AutoScalingGrants"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid    = "CloudWatchLogsEncryption"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
    }
  }

  # Cross-account AMI promotion: a consumer account copies the AMI and needs to decrypt the source snapshot.
  dynamic "statement" {
    for_each = length(var.ami_consumer_account_ids) > 0 ? [1] : []

    content {
      sid    = "AmiCopyConsumerAccounts"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = [for id in var.ami_consumer_account_ids : "arn:${local.partition}:iam::${id}:root"]
      }
    }
  }

  # CloudWatch alarms publish to the encrypted SNS topic using their service principal.
  statement {
    sid       = "CloudWatchAlarmsToEncryptedTopic"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "${var.name} encryption key (EBS, logs, alerts)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = local.common_tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-ebs"
  target_key_id = aws_kms_key.this.key_id
}
