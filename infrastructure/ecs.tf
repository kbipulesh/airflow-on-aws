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