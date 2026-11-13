resource "aws_autoscaling_policy" "cpu" {
  name                      = "${var.name}-cpu-target"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = var.instance_warmup_seconds

  target_tracking_configuration {
    target_value = var.cpu_target_percent

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}

# Scale on demand per instance. Both target tracking policies must agree before scale-in,
# and either one can drive scale-out.
resource "aws_autoscaling_policy" "requests" {
  name                      = "${var.name}-requests-target"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = var.instance_warmup_seconds

  target_tracking_configuration {
    target_value = var.requests_per_target

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
  }
}

resource "aws_autoscaling_schedule" "this" {
  for_each = var.scheduled_actions

  scheduled_action_name  = each.key
  autoscaling_group_name = aws_autoscaling_group.this.name
  recurrence             = each.value.recurrence
  time_zone              = each.value.time_zone
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.desired_capacity
}
