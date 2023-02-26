resource "aws_alb" "airflow_alb" {
  name            = "${var.project_name}-${var.stage}-alb"
  subnets         = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]
  security_groups = [aws_security_group.application_load_balancer.id]

  access_logs {
    bucket = "${var.project_name}-${var.stage}-elb-access-logs-${var.aws_region}"
    enabled = true
  }
}

resource "aws_alb_target_group" "airflow_web_server" {
  name        = "${var.project_name}-${var.stage}-web-server"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"

  health_check {
    interval            = 10
    port                = 8080
    protocol            = "HTTP"
    path                = "/health"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 3
  }
}

# port exposed from the application load balancer
resource "aws_alb_listener" "airflow_web_server" {
  load_balancer_arn = aws_alb.airflow_alb.id
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = data.aws_acm_certificate.cert.arn
  ssl_policy        = "ELBSecurityPolicy-2016-08"

  default_action {
    target_group_arn = aws_alb_target_group.airflow_web_server.id
    type             = "forward"
  }
}

resource "aws_alb_listener" "airflow_web_server_http" {
  load_balancer_arn = aws_alb.airflow_alb.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_302"
    }
  }
}