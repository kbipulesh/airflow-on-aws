resource "aws_security_group" "flower" {
  name        = "${var.project_name}-${var.stage}-flower-sg"
  description = "Allow all inbound traffic for Flower"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 5555
    to_port     = 5555
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
    Name = "${var.project_name}-${var.stage}-flower-sg"
  }
}


resource "aws_ecs_task_definition" "flower" {
  family                   = "${var.project_name}-${var.stage}-flower"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_iam_role.arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512" # the valid CPU amount for 2 GB is from from 256 to 1024
  memory                   = "1024"
  container_definitions    = <<EOF
[
  {
    "name": "airflow_flower",
    "image": ${replace(jsonencode("${aws_ecr_repository.docker_repository.repository_url}:${var.image_version}"), "/\"([0-9]+\\.?[0-9]*)\"/", "$1")} ,
    "essential": true,
    "portMappings": [
      {
        "protocol": "tcp",
        "containerPort": 5555,
        "hostPort": 5555
      }
    ],
    "command": [
        "flower"
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
      }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${var.log_group_name}/${var.project_name}-${var.stage}",
            "awslogs-region": "${var.aws_region}",
            "awslogs-stream-prefix": "flower"
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
