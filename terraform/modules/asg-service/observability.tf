resource "aws_cloudwatch_log_group" "app" {
  name              = var.app_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
  tags              = local.common_tags
}

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = aws_kms_key.this.arn
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alarm_email_endpoints)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  alb_dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}

# Rollback alarm 1: fleet error rate. Used by the instance refresh. A bad AMI that fails requests
# pushes this above the threshold and the refresh rolls back to the previous launch template.
resource "aws_cloudwatch_metric_alarm" "rollback_5xx" {
  alarm_name          = "${var.name}-rollback-5xx-rate"
  alarm_description   = "Target 5xx rate above ${var.rollback_5xx_percent}% for 2 of 3 minutes. Used as an instance refresh rollback alarm."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rollback_5xx_percent
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(requests > 0, (errors / requests) * 100, 0)"
    label       = "Target 5xx percentage"
    return_data = true
  }

  metric_query {
    id = "errors"

    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = local.alb_dimensions
    }
  }

  metric_query {
    id = "requests"

    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = local.alb_dimensions
    }
  }
}

# Rollback alarm 2: latency regression. A slow AMI with few errors is still a bad release.
resource "aws_cloudwatch_metric_alarm" "rollback_latency" {
  alarm_name          = "${var.name}-rollback-p95-latency"
  alarm_description   = "p95 target response time above ${var.rollback_p95_latency_seconds}s for 3 of 5 minutes. Used as an instance refresh rollback alarm."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rollback_p95_latency_seconds
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  namespace          = "AWS/ApplicationELB"
  metric_name        = "TargetResponseTime"
  extended_statistic = "p95"
  period             = 60
  dimensions         = local.alb_dimensions
}

# Paging alarms. These are deliberately not rollback alarms: unhealthy hosts appear normally
# while a refresh replaces instances, so using them for rollback would cause false rollbacks.
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "${var.name}-unhealthy-targets"
  alarm_description   = "At least one target has failed health checks for 5 minutes. Check runbook: unhealthy targets and 502s."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  period      = 60
  statistic   = "Maximum"
  dimensions  = local.alb_dimensions
}

resource "aws_cloudwatch_metric_alarm" "in_service_below_minimum" {
  alarm_name          = "${var.name}-capacity-below-minimum"
  alarm_description   = "In-service instances below the ASG minimum for 5 minutes. Spot reclaim or launch failures are the usual cause."
  comparison_operator = "LessThanThreshold"
  threshold           = var.min_size
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  namespace   = "AWS/AutoScaling"
  metric_name = "GroupInServiceInstances"
  period      = 60
  statistic   = "Minimum"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }
}

resource "aws_cloudwatch_metric_alarm" "fleet_cpu_high" {
  alarm_name          = "${var.name}-fleet-cpu-high"
  alarm_description   = "Average fleet CPU above 85% for 15 minutes. Target tracking should already be scaling out; this means it cannot."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  period      = 300
  statistic   = "Average"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }
}
