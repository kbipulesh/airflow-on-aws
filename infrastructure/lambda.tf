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