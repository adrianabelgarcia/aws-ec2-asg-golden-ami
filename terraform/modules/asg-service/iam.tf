data "aws_iam_policy_document" "instance_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
  description        = "Runtime role for ${var.name} instances. Session Manager access plus scoped logs, metrics and lifecycle permissions."
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance_scoped" {
  statement {
    sid    = "WriteAppAndAuditLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.app_log_group_name}:*",
    ]
  }

  # PutMetricData does not support resource-level permissions, so the namespace condition is the boundary.
  statement {
    sid       = "PublishAppMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["AcmeDemo/SampleApp"]
    }
  }

  # Lets the drain hook finish its own ASG lifecycle action and nothing else in the group.
  statement {
    sid       = "CompleteOwnLifecycleHook"
    effect    = "Allow"
    actions   = ["autoscaling:CompleteLifecycleAction"]
    resources = ["arn:${local.partition}:autoscaling:${local.region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"]
  }

  dynamic "statement" {
    for_each = length(var.app_s3_read_arns) > 0 ? [1] : []

    content {
      sid       = "ReadAppConfigObjects"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = var.app_s3_read_arns
    }
  }
}

resource "aws_iam_role_policy" "instance_scoped" {
  name   = "${var.name}-scoped"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance_scoped.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance"
  role = aws_iam_role.instance.name
  tags = local.common_tags
}
