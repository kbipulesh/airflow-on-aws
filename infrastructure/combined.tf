//infrastructure/airflow_web_server.tf

resource "aws_security_group" "application_load_balancer" {
  name        = "${var.project_name}-${var.stage}-alb-web-sg"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ingress from HTTPS"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ingress from HTTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.stage}-alb-web-sg"
  }
}


resource "aws_security_group" "web_server_ecs_internal" {
  name        = "${var.project_name}-${var.stage}-web-server-ecs-internal-sg"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.application_load_balancer.id]
    cidr_blocks     = []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.stage}-web-server-ecs-internal-sg"
  }
}


resource "aws_ecs_task_definition" "web_server" {
  family = "${var.project_name}-${var.stage}-web-server"
  # container_definitions = file("airflow-components/web_server.json")
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_iam_role.arn
  task_role_arn            = aws_iam_role.ecs_task_iam_role.arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048" # the valid CPU amount for 2 GB is from from 256 to 1024
  memory                   = "8192"
  container_definitions    = <<EOF
[
  {
    "name": "airflow_web_server",
    "image": ${replace(jsonencode("${aws_ecr_repository.docker_repository.repository_url}:${var.image_version}"), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")} ,
    "essential": true,
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080
      }
    ],
    "command": [
        "webserver"
    ],
    "mountPoints": [
      {
        "sourceVolume": "efs-storage-dags-AP",
        "containerPath": "/opt/airflow/dags"
      },
      {
        "sourceVolume": "efs-storage-logs-AP",
        "containerPath": "/opt/airflow/logs"
      },
      {
        "sourceVolume": "efs-storage-plugins-AP",
        "containerPath": "/opt/airflow/plugins"
      },
      {
        "sourceVolume": "efs-storage-files-AP",
        "containerPath": "/opt/airflow/files"
      }
    ],
    "environment": [
      {
        "name": "REDIS_HOST",
        "value": ${replace(jsonencode(aws_elasticache_cluster.celery_backend.cache_nodes.0.address), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")}
      },
      {
        "name": "REDIS_PORT",
        "value": "6379"
      },
      {
        "name": "POSTGRES_HOST",
        "value": ${replace(jsonencode(aws_db_instance.metadata_db.address), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")}
      },
      {
        "name": "POSTGRES_PORT",
        "value": "5432"
      },
      {
          "name": "POSTGRES_USER",
          "value": "airflow"
      },
      {
          "name": "POSTGRES_DB",
          "value": "airflow"
      },
      {
        "name": "AIRFLOW_BASE_URL",
        "value": "http://localhost:8080"
      },
      {
        "name": "ENABLE_REMOTE_LOGGING",
        "value": "False"
      },
      {
        "name": "STAGE",
        "value": "${var.stage}"
      }
    ],
    "secrets": [
      {
        "name": "FERNET_KEY",
        "valueFrom": ${jsonencode(aws_secretsmanager_secret.fernet_key.arn)}
      },
      {
        "name": "POSTGRES_PASSWORD",
        "valueFrom": ${jsonencode(aws_secretsmanager_secret_version.postgres_db_cred.arn)}
      },
      {
        "name": "OKTA_DOMAIN",
        "valueFrom": "${aws_secretsmanager_secret.okta_config.arn}:issuer_domain::"
      },
      {
        "name": "OKTA_KEY",
        "valueFrom": "${aws_secretsmanager_secret.okta_config.arn}:client_id::"
      },
      {
        "name": "OKTA_SECRET",
        "valueFrom": "${aws_secretsmanager_secret.okta_config.arn}:client_secret::"
      },
      {
        "name": "AIRFLOW__WEBSERVER__SECRET_KEY",
        "valueFrom": ${jsonencode(aws_secretsmanager_secret.ws_secret_key.arn)}
      },
      {
        "name": "SMTP_MAIL_FROM",
        "valueFrom": "${aws_secretsmanager_secret.smtp_config.arn}:mail_from::"
      },
      {
        "name": "SMTP_USER",
        "valueFrom": "${aws_secretsmanager_secret.smtp_config.arn}:user::"
      },
      {
        "name": "SMTP_PASSWORD",
        "valueFrom": "${aws_secretsmanager_secret.smtp_config.arn}:password::"
      }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${var.log_group_name}/${var.project_name}-${var.stage}",
            "awslogs-region": "${var.aws_region}",
            "awslogs-stream-prefix": "web_server"
        }
    }
  }
]
EOF

  volume {
    name = "efs-storage-dags-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-dags.id
      }
    }
  }

  volume {
    name = "efs-storage-logs-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-logs.id
      }
    }
  }

  volume {
    name = "efs-storage-plugins-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-plugins.id
      }
    }
  }

  volume {
    name = "efs-storage-files-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-files.id
      }
    }
  }
}


//infrastructure/airflow_web_server_lb.tf

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



//infrastructure/airflow_workers.tf

resource "aws_security_group" "workers" {
  name        = "${var.project_name}-${var.stage}-workers-sg"
  description = "Airflow Celery Workers security group"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 8793
    to_port     = 8793
    protocol    = "tcp"
    cidr_blocks = ["${var.base_cidr_block}/16"]
  }

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["${var.base_cidr_block}/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.stage}-workers-sg"
  }
}


resource "aws_ecs_task_definition" "workers" {
  family                   = "${var.project_name}-${var.stage}-workers"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_iam_role.arn
  task_role_arn            = aws_iam_role.ecs_task_iam_role.arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "8192" # the valid CPU amount for 2 GB is from from 256 to 1024
  container_definitions    = <<EOF
[
  {
    "name": "airflow_workers",
    "image": ${replace(jsonencode("${aws_ecr_repository.docker_repository.repository_url}:${var.image_version}"), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")} ,
    "essential": true,
    "portMappings": [
      {
        "containerPort": 8793,
        "hostPort": 8793
      }
    ],
    "command": [
        "worker"
    ],
    "mountPoints": [
      {
        "sourceVolume": "efs-storage-dags-AP",
        "containerPath": "/opt/airflow/dags"
      },
      {
        "sourceVolume": "efs-storage-logs-AP",
        "containerPath": "/opt/airflow/logs"
      },
      {
        "sourceVolume": "efs-storage-plugins-AP",
        "containerPath": "/opt/airflow/plugins"
      },
      {
        "sourceVolume": "efs-storage-files-AP",
        "containerPath": "/opt/airflow/files"
      }
    ],
    "environment": [
      {
        "name": "REDIS_HOST",
        "value": ${replace(jsonencode(aws_elasticache_cluster.celery_backend.cache_nodes.0.address), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")}
      },
      {
        "name": "REDIS_PORT",
        "value": "6379"
      },
      {
        "name": "POSTGRES_HOST",
        "value": ${replace(jsonencode(aws_db_instance.metadata_db.address), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")}
      },
      {
        "name": "POSTGRES_PORT",
        "value": "5432"
      },
      {
          "name": "POSTGRES_USER",
          "value": "airflow"
      },
      {
          "name": "POSTGRES_DB",
          "value": "airflow"
      },
      {
        "name": "AIRFLOW_BASE_URL",
        "value": "http://localhost:8080"
      },
      {
        "name": "ENABLE_REMOTE_LOGGING",
        "value": "False"
      },
      {
        "name": "STAGE",
        "value": "${var.stage}"
      }
    ],
    "secrets": [
      {
        "name": "FERNET_KEY",
        "valueFrom": ${jsonencode(aws_secretsmanager_secret.fernet_key.arn)}
      },
      {
        "name": "POSTGRES_PASSWORD",
        "valueFrom": ${jsonencode(aws_secretsmanager_secret_version.postgres_db_cred.arn)}
      },
      {
        "name": "OKTA_CONFIG",
        "valueFrom": ${jsonencode(aws_secretsmanager_secret.okta_config.arn)}
      },
      {
        "name": "AIRFLOW__WEBSERVER__SECRET_KEY",
        "valueFrom": ${jsonencode(aws_secretsmanager_secret.ws_secret_key.arn)}
      },
      {
        "name": "SMTP_MAIL_FROM",
        "valueFrom": "${aws_secretsmanager_secret.smtp_config.arn}:mail_from::"
      },
      {
        "name": "SMTP_USER",
        "valueFrom": "${aws_secretsmanager_secret.smtp_config.arn}:user::"
      },
      {
        "name": "SMTP_PASSWORD",
        "valueFrom": "${aws_secretsmanager_secret.smtp_config.arn}:password::"
      }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${var.log_group_name}/${var.project_name}-${var.stage}",
            "awslogs-region": "${var.aws_region}",
            "awslogs-stream-prefix": "workers"
        }
    }
  }
]
EOF

  volume {
    name = "efs-storage-dags-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-dags.id
      }
    }
  }

  volume {
    name = "efs-storage-logs-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-logs.id
      }
    }
  }

  volume {
    name = "efs-storage-plugins-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-plugins.id
      }
    }
  }

  volume {
    name = "efs-storage-files-AP"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.fs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.access-point-files.id
      }
    }
  }
}




// infrastructure/config.tf

variable "aws_region" {
  default = "us-east-1"
}

variable "aws_profile" {
  default = "pam-de-123"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "project_name" {
  default = "pam-airflow"
}

variable "stage" {
  default = "qa"
}

variable "base_cidr_block" {
  default = "10.0.0.0"
}

variable "log_group_name" {
  default = "ecs/fargate"
}

variable "image_version" {
  default = "latest"
}

variable "metadata_db_instance_type" {
  default = "db.t3.micro"
}

variable "celery_backend_instance_type" {
  default = "cache.t2.small"
}



//infrastructure/data.tf

data "aws_caller_identity" "current" {}

# SSL Certificate
data "aws_acm_certificate" "cert" {
  domain   = "airflow.${var.stage}.pam.mckinsey.com"
  statuses = ["ISSUED"]
}


data "external" "my-ip" {
  program = ["bash", "-c", "curl -s 'https://api.ipify.org?format=json'"]
}


data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../../lambda"
  output_path = "../lambda.zip"
}

//infrastructure/ec2.tf

resource "aws_security_group" "ec2-for-efs-mt-sg" {
  name        = "${var.project_name}-${var.stage}-efs-ec2-sg"
  description = "Amazon EFS, SG for EC2 instance"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.base_cidr_block}/16", "${data.external.my-ip.result["ip"]}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.stage}-efs-ec2-sg"
  }
}

resource "aws_security_group" "efs-mt-sg" {
  name        = "${var.project_name}-${var.stage}-mt-sg"
  description = "Amazon EFS, SG for mount target"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    cidr_blocks     = []
    security_groups = [aws_security_group.ec2-for-efs-mt-sg.id]
  }

  tags = {
    Name = "${var.project_name}-${var.stage}-mt-sg"
  }
}

#resource "aws_key_pair" "key-pair" {
#  public_key = ""
#  key_name   = "${var.project_name}-${var.stage}-key-pair"
#}
#
#resource "aws_instance" "ec2-for-efs-mt" {
#  instance_type               = "t2.micro"
#  ami                         = "ami-0eec024dbbe865d48"
#  associate_public_ip_address = false
#  key_name                    = "${var.project_name}-${var.stage}-key-pair"
#  vpc_security_group_ids      = [aws_security_group.ec2-for-efs-mt-sg.id]
#  subnet_id                   = aws_subnet.private-subnet-1.id
#
#  tags = {
#    Name = "${var.project_name}-${var.stage}-ec2-for-efs-mt"
#  }
#}



//infrastructure/ecs.tf

resource "aws_ecr_repository" "docker_repository" {
  name = "${var.project_name}-${var.stage}"
}

resource "aws_ecr_lifecycle_policy" "docker_repository_lifecycly" {
  repository = aws_ecr_repository.docker_repository.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep only the latest 5 images",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 5
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.project_name}-${var.stage}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "${var.log_group_name}/${var.project_name}-${var.stage}"
  retention_in_days = 5
}

resource "aws_iam_role" "ecs_task_iam_role" {
  name        = "${var.project_name}-${var.stage}-ecs-task-role"
  description = "Allow ECS tasks to access AWS resources"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "ecs_task_policy" {
  name = "${var.project_name}-${var.stage}-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
          "secretsmanager:GetSecretValue"
      ],
      "Effect": "Allow",
      "Resource": [
          "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.stage}/variables/*",
          "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.stage}/connections/*",
          "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.stage}/config/*"
      ]
    },
    {
        "Action": [
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientRootAccess"
        ],
        "Effect": "Allow",
        "Resource": ${replace(jsonencode(aws_efs_file_system.fs.arn), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")},
        "Condition": {
            "Bool": {
                "elasticfilesystem:AccessedViaMountTarget": "true"
            }
        }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ecs_task_iam_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}



//infrastructure/ecs_service.tf

resource "aws_ecs_service" "web_server_service" {
  name                   = "${var.project_name}-${var.stage}-web-server"
  cluster                = aws_ecs_cluster.ecs_cluster.id
  task_definition        = aws_ecs_task_definition.web_server.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 180

  network_configuration {
    security_groups  = [aws_security_group.web_server_ecs_internal.id]
    subnets          = [aws_subnet.private-subnet-1.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.airflow_web_server.id
    container_name   = "airflow_web_server"
    container_port   = 8080
  }

  depends_on = [
    aws_db_instance.metadata_db,
    aws_elasticache_cluster.celery_backend,
    aws_alb_listener.airflow_web_server,
  ]
}

resource "aws_ecs_service" "scheduler_service" {
  name            = "${var.project_name}-${var.stage}-scheduler"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.scheduler.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.scheduler.id]
    subnets          = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    assign_public_ip = false # when using a NAT can be put to false, or when ECS Private Link is enabled
  }

  depends_on = [
    aws_db_instance.metadata_db,
    aws_elasticache_cluster.celery_backend,
  ]
}

resource "aws_ecs_service" "workers_service" {
  name                   = "${var.project_name}-${var.stage}-workers"
  cluster                = aws_ecs_cluster.ecs_cluster.id
  task_definition        = aws_ecs_task_definition.workers.arn
  desired_count          = 2
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    security_groups  = [aws_security_group.workers.id]
    subnets          = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    assign_public_ip = false # when using a NAT can be put to false, or when ECS Private Link is enabled
  }

  depends_on = [
    aws_db_instance.metadata_db,
    aws_elasticache_cluster.celery_backend,
  ]
}

resource "aws_ecs_service" "flower_service" {
  name            = "${var.project_name}-${var.stage}-flower"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.flower.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.flower.id]
    subnets          = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_db_instance.metadata_db,
    aws_elasticache_cluster.celery_backend,
  ]
}


//infrastructure/lambda.tf

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-${var.stage}-lambda-sg"
  description = "Security group for Lambda"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    "Name" = "${var.project_name}-${var.stage}-lambda-sg"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.base_cidr_block}/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.base_cidr_block}/16"]
  }

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]

  }
}

resource "aws_iam_role" "lambda_iam_role" {
  name        = "${var.project_name}-${var.stage}-lamda-role"
  description = "Allow Lambda to access AWS resources"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-${var.stage}-lambda-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Action": [
            "ec2:CreateNetworkInterface",
            "ec2:DeleteNetworkInterface",
            "ec2:DescribeNetworkInterfaces"
        ],
        "Resource": "*",
        "Effect": "Allow",
        "Sid": ""
    },
    {
      "Action": "elasticfilesystem:ClientWrite",
      "Resource": "arn:aws:elasticfilesystem:us-east-1:${data.aws_caller_identity.current.account_id}:file-system/${aws_efs_file_system.fs.id}",
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": [
            "s3:GetObject",
            "s3:ListBucket"
        ],
      "Resource": [
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts",
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts/dags/*",
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts/plugins/*",
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts/files/*"
        ],
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": "logs:CreateLogGroup",
      "Resource": "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*",
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ],
      "Resource": "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.stage}-*:*",
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach_lambda_policy" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


resource "aws_s3_bucket" "airflow_artifacts_bucket" {
  bucket = "${var.project_name}-${var.stage}-artifacts"
}


# DAGs deployment
resource "aws_lambda_function" "lambda_for_dags_deployment" {
  function_name    = "${var.project_name}-${var.stage}-dags-deployment-lambda"
  description      = "Lambda to deploy S3 dags to EFS"
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = "../lambda.zip"
  handler          = "s3_to_efs_sync.lambda_handler"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  runtime = "python3.8"

  environment {
    variables = {
      foo = "bar"
    }
  }

  file_system_config {
    # EFS file system access point ARN
    arn = aws_efs_access_point.access-point-dags.arn

    # Local mount path inside the lambda function. Must start with '/mnt/'.
    local_mount_path = "/mnt/dags"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Explicitly declare dependency on EFS mount target.
  # When creating or updating Lambda functions, mount target must be in 'available' lifecycle state.
  depends_on = [aws_efs_mount_target.efs-ec2-mount-target-1, aws_efs_mount_target.efs-ec2-mount-target-2]
}


resource "aws_lambda_permission" "allow_bucket_dags" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda_for_dags_deployment.arn
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_s3_bucket.airflow_artifacts_bucket.arn
}


# Plugins deployment
resource "aws_lambda_function" "lambda_for_plugins_deployment" {
  function_name    = "${var.project_name}-${var.stage}-plugins-deployment-lambda"
  description      = "Lambda to deploy S3 Plugins to EFS"
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = "../lambda.zip"
  handler          = "s3_to_efs_sync.lambda_handler"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  runtime = "python3.8"

  environment {
    variables = {
      foo = "bar"
    }
  }

  file_system_config {
    # EFS file system access point ARN
    arn = aws_efs_access_point.access-point-plugins.arn

    # Local mount path inside the lambda function. Must start with '/mnt/'.
    local_mount_path = "/mnt/plugins"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Explicitly declare dependency on EFS mount target.
  # When creating or updating Lambda functions, mount target must be in 'available' lifecycle state.
  depends_on = [aws_efs_mount_target.efs-ec2-mount-target-1, aws_efs_mount_target.efs-ec2-mount-target-2]
}


resource "aws_lambda_permission" "allow_bucket_plugins" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda_for_plugins_deployment.arn
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_s3_bucket.airflow_artifacts_bucket.arn
}


# Files deployment
resource "aws_lambda_function" "lambda_for_files_deployment" {
  function_name    = "${var.project_name}-${var.stage}-files-deployment-lambda"
  description      = "Lambda to deploy S3 Files to EFS"
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = "../lambda.zip"
  handler          = "s3_to_efs_sync.lambda_handler"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  runtime = "python3.8"

  environment {
    variables = {
      foo = "bar"
    }
  }

  file_system_config {
    # EFS file system access point ARN
    arn = aws_efs_access_point.access-point-files.arn

    # Local mount path inside the lambda function. Must start with '/mnt/'.
    local_mount_path = "/mnt/files"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Explicitly declare dependency on EFS mount target.
  # When creating or updating Lambda functions, mount target must be in 'available' lifecycle state.
  depends_on = [aws_efs_mount_target.efs-ec2-mount-target-1, aws_efs_mount_target.efs-ec2-mount-target-2]
}


resource "aws_lambda_permission" "allow_bucket_files" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda_for_files_deployment.arn
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_s3_bucket.airflow_artifacts_bucket.arn
}


# S3 bucket notification to invoke lambdas
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.airflow_artifacts_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_for_dags_deployment.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "dags/"
    filter_suffix       = ".py"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_for_plugins_deployment.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "plugins/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_for_files_deployment.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "files/"
  }

  depends_on = [aws_lambda_permission.allow_bucket_dags, aws_lambda_permission.allow_bucket_plugins,
  aws_lambda_permission.allow_bucket_files]
}


// infrastructure/network.tf

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-${var.stage}-lambda-sg"
  description = "Security group for Lambda"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    "Name" = "${var.project_name}-${var.stage}-lambda-sg"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.base_cidr_block}/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.base_cidr_block}/16"]
  }

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]

  }
}

resource "aws_iam_role" "lambda_iam_role" {
  name        = "${var.project_name}-${var.stage}-lamda-role"
  description = "Allow Lambda to access AWS resources"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-${var.stage}-lambda-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Action": [
            "ec2:CreateNetworkInterface",
            "ec2:DeleteNetworkInterface",
            "ec2:DescribeNetworkInterfaces"
        ],
        "Resource": "*",
        "Effect": "Allow",
        "Sid": ""
    },
    {
      "Action": "elasticfilesystem:ClientWrite",
      "Resource": "arn:aws:elasticfilesystem:us-east-1:${data.aws_caller_identity.current.account_id}:file-system/${aws_efs_file_system.fs.id}",
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": [
            "s3:GetObject",
            "s3:ListBucket"
        ],
      "Resource": [
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts",
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts/dags/*",
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts/plugins/*",
            "arn:aws:s3:::${var.project_name}-${var.stage}-artifacts/files/*"
        ],
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": "logs:CreateLogGroup",
      "Resource": "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*",
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ],
      "Resource": "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.stage}-*:*",
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach_lambda_policy" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


resource "aws_s3_bucket" "airflow_artifacts_bucket" {
  bucket = "${var.project_name}-${var.stage}-artifacts"
}


# DAGs deployment
resource "aws_lambda_function" "lambda_for_dags_deployment" {
  function_name    = "${var.project_name}-${var.stage}-dags-deployment-lambda"
  description      = "Lambda to deploy S3 dags to EFS"
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = "../lambda.zip"
  handler          = "s3_to_efs_sync.lambda_handler"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  runtime = "python3.8"

  environment {
    variables = {
      foo = "bar"
    }
  }

  file_system_config {
    # EFS file system access point ARN
    arn = aws_efs_access_point.access-point-dags.arn

    # Local mount path inside the lambda function. Must start with '/mnt/'.
    local_mount_path = "/mnt/dags"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Explicitly declare dependency on EFS mount target.
  # When creating or updating Lambda functions, mount target must be in 'available' lifecycle state.
  depends_on = [aws_efs_mount_target.efs-ec2-mount-target-1, aws_efs_mount_target.efs-ec2-mount-target-2]
}


resource "aws_lambda_permission" "allow_bucket_dags" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda_for_dags_deployment.arn
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_s3_bucket.airflow_artifacts_bucket.arn
}


# Plugins deployment
resource "aws_lambda_function" "lambda_for_plugins_deployment" {
  function_name    = "${var.project_name}-${var.stage}-plugins-deployment-lambda"
  description      = "Lambda to deploy S3 Plugins to EFS"
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = "../lambda.zip"
  handler          = "s3_to_efs_sync.lambda_handler"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  runtime = "python3.8"

  environment {
    variables = {
      foo = "bar"
    }
  }

  file_system_config {
    # EFS file system access point ARN
    arn = aws_efs_access_point.access-point-plugins.arn

    # Local mount path inside the lambda function. Must start with '/mnt/'.
    local_mount_path = "/mnt/plugins"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Explicitly declare dependency on EFS mount target.
  # When creating or updating Lambda functions, mount target must be in 'available' lifecycle state.
  depends_on = [aws_efs_mount_target.efs-ec2-mount-target-1, aws_efs_mount_target.efs-ec2-mount-target-2]
}


resource "aws_lambda_permission" "allow_bucket_plugins" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda_for_plugins_deployment.arn
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_s3_bucket.airflow_artifacts_bucket.arn
}


# Files deployment
resource "aws_lambda_function" "lambda_for_files_deployment" {
  function_name    = "${var.project_name}-${var.stage}-files-deployment-lambda"
  description      = "Lambda to deploy S3 Files to EFS"
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = "../lambda.zip"
  handler          = "s3_to_efs_sync.lambda_handler"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  runtime = "python3.8"

  environment {
    variables = {
      foo = "bar"
    }
  }

  file_system_config {
    # EFS file system access point ARN
    arn = aws_efs_access_point.access-point-files.arn

    # Local mount path inside the lambda function. Must start with '/mnt/'.
    local_mount_path = "/mnt/files"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Explicitly declare dependency on EFS mount target.
  # When creating or updating Lambda functions, mount target must be in 'available' lifecycle state.
  depends_on = [aws_efs_mount_target.efs-ec2-mount-target-1, aws_efs_mount_target.efs-ec2-mount-target-2]
}


resource "aws_lambda_permission" "allow_bucket_files" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda_for_files_deployment.arn
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_s3_bucket.airflow_artifacts_bucket.arn
}


# S3 bucket notification to invoke lambdas
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.airflow_artifacts_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_for_dags_deployment.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "dags/"
    filter_suffix       = ".py"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_for_plugins_deployment.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "plugins/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_for_files_deployment.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "files/"
  }

  depends_on = [aws_lambda_permission.allow_bucket_dags, aws_lambda_permission.allow_bucket_plugins,
  aws_lambda_permission.allow_bucket_files]
}



