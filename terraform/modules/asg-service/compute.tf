resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  description            = "Golden AMI launch template for ${var.name}"
  image_id               = local.ami_id
  update_default_version = true
  ebs_optimized          = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  # IMDSv2 only, and a hop limit of 1 so containers or other network hops cannot reach metadata.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [aws_security_group.instance.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.this.arn
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    service_name        = var.service_name
    environment         = var.environment
    asg_name            = local.asg_name
    lifecycle_hook_name = local.hook_name
    region              = local.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name       = "${var.name}-instance"
      PatchGroup = local.patch_group
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name   = "${var.name}-root"
      Backup = var.enable_backup ? "daily" : "none"
    })
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = local.asg_name
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = var.instance_warmup_seconds
  capacity_rebalance        = true
  termination_policies      = ["OldestLaunchTemplate", "OldestInstance"]
  wait_for_capacity_timeout = "15m"
  metrics_granularity       = "1Minute"
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  # Mixed instances: a fixed on-demand base, then Spot from several instance types, placed by
  # capacity-optimized allocation so interruptions are less frequent.
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.this.id
        version            = aws_launch_template.this.latest_version
      }

      dynamic "override" {
        for_each = var.instance_types

        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_allocation_strategy            = "prioritized"
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }

  # A launch template version change starts a rolling replacement. Health and rollback are
  # governed by the rollback alarms in observability.tf.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = var.refresh_min_healthy_percentage
      instance_warmup        = var.instance_warmup_seconds
      skip_matching          = true
      checkpoint_percentages = var.refresh_checkpoint_percentages
      checkpoint_delay       = var.refresh_checkpoint_delay
      auto_rollback          = var.refresh_auto_rollback

      alarm_specification {
        alarms = [
          aws_cloudwatch_metric_alarm.rollback_5xx.alarm_name,
          aws_cloudwatch_metric_alarm.rollback_latency.alarm_name,
        ]
      }
    }
  }

  dynamic "warm_pool" {
    for_each = var.warm_pool.enabled ? [var.warm_pool] : []

    content {
      pool_state                  = warm_pool.value.pool_state
      min_size                    = warm_pool.value.min_size
      max_group_prepared_capacity = warm_pool.value.max_group_prepared_capacity

      instance_reuse_policy {
        reuse_on_scale_in = true
      }
    }
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${var.name}-instance", PatchGroup = local.patch_group })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    # Target tracking owns desired capacity after creation.
    ignore_changes = [desired_capacity]
  }
}

# Drain on scale-in and refresh: the instance stops sample-app (which fails health and finishes
# in-flight requests) before the hook is completed, so the ASG terminates it only after draining.
resource "aws_autoscaling_lifecycle_hook" "drain" {
  name                   = local.hook_name
  autoscaling_group_name = aws_autoscaling_group.this.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  default_result         = "CONTINUE"
  heartbeat_timeout      = var.lifecycle_drain_timeout
}
