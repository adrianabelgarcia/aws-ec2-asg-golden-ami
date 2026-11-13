# Application Load Balancer, target group and listeners.

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150: Deletion protection is driven by var.deletion_protection, true in prod. Staging turns it off so it can be torn down; checkov cannot resolve that variable across the module call.
  name                       = local.alb_name
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"
  enable_deletion_protection = var.deletion_protection
  enable_http2               = true
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = merge(local.common_tags, { Name = local.alb_name })

  depends_on = [aws_s3_bucket_policy.alb_logs]
}
resource "aws_lb_target_group" "app" {
  name                          = local.tg_name
  port                          = var.app_port
  protocol                      = "HTTP"
  vpc_id                        = var.vpc_id
  target_type                   = "instance"
  deregistration_delay          = var.deregistration_delay
  load_balancing_algorithm_type = "least_outstanding_requests"

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, { Name = local.tg_name })
}
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
