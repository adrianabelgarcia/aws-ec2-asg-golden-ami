# Security groups: the internet reaches only the ALB; the ALB reaches only the app port on the
# instances; instances have no inbound access from anywhere but the ALB.

# Security groups: the internet reaches only the ALB; the ALB reaches only the app port on the
# instances; instances have no inbound access from anywhere but the ALB.
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public ALB for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name}-alb" })
}
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  #checkov:skip=CKV_AWS_260: Port 80 exists only to answer with a 301 redirect to HTTPS. No application traffic is served on it.
  security_group_id = aws_security_group.alb.id
  description       = "HTTP only to redirect to HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_instances" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to application instances on the app port"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.instance.id
}
resource "aws_security_group" "instance" {
  name        = "${var.name}-instance"
  description = "Application instances for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name}-instance" })
}
resource "aws_vpc_security_group_ingress_rule" "instance_from_alb" {
  security_group_id            = aws_security_group.instance.id
  description                  = "Application traffic from the ALB only"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}
resource "aws_vpc_security_group_egress_rule" "instance_https" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTPS to AWS APIs (SSM, CloudWatch, Auto Scaling) and package repositories"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_egress_rule" "instance_ntp" {
  security_group_id = aws_security_group.instance.id
  description       = "NTP from the AWS time sync service"
  ip_protocol       = "udp"
  from_port         = 123
  to_port           = 123
  cidr_ipv4         = "169.254.169.123/32"
}
# Access logs bucket. ALB access logs can only be written with SSE-S3, not SSE-KMS.
# WAF logs go to a log group whose name must start with aws-waf-logs-. Credentials are redacted.
