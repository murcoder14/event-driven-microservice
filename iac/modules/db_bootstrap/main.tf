data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/package"
  output_path = "${path.module}/bootstrap_lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "db_bootstrap_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy" "lambda_secrets_policy" {
  name        = "db_bootstrap_lambda_secrets"
  description = "Allows Lambda to fetch DB secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "secretsmanager:GetSecretValue"
        Effect   = "Allow"
        Resource = [
          var.master_secret_arn,
          var.tmpower_secret_arn,
          var.tmapp_secret_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_secrets_policy.arn
}

resource "aws_security_group" "lambda_sg" {
  name        = "db-bootstrap-lambda-sg"
  vpc_id      = var.vpc_id
  description = "Security group for DB bootstrap lambda"
  revoke_rules_on_delete = true

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_function" "bootstrapper" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "db-bootstrapper"
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap_lambda.handler"
  runtime          = "python3.12"
  timeout          = 120
  memory_size      = 512

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST            = var.db_host
      DB_NAME            = var.db_name
      MASTER_SECRET_ARN  = var.master_secret_arn
      TMPOWER_SECRET_ARN = var.tmpower_secret_arn
      TMAPP_SECRET_ARN   = var.tmapp_secret_arn
    }
  }
}

# Automatically invoke the bootstrapper whenever the code or configuration changes
resource "null_resource" "invoke_bootstrapper" {
  triggers = {
    code_hash = aws_lambda_function.bootstrapper.source_code_hash
    db_host   = var.db_host
  }

  provisioner "local-exec" {
    command = "aws lambda invoke --function-name ${aws_lambda_function.bootstrapper.function_name} --payload '{}' /dev/null"
  }

  depends_on = [aws_lambda_function.bootstrapper]
}

# EventBridge Rule: Trigger Lambda when RDS becomes available
resource "aws_cloudwatch_event_rule" "rds_available" {
  name        = "rds-bootstrap-trigger"
  description = "Trigger DB bootstrap Lambda when RDS instance becomes available"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Instance Event"]
    detail = {
      EventCategories = ["availability"]
      Message = [{
        prefix = "DB instance started"
      }]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.rds_available.name
  target_id = "TriggerBootstrapLambda"
  arn       = aws_lambda_function.bootstrapper.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bootstrapper.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_available.arn
}

variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "db_host" { type = string }
variable "db_name" { type = string }
variable "master_secret_arn" { type = string }
variable "tmpower_secret_arn" { type = string }
variable "tmapp_secret_arn" { type = string }

output "lambda_security_group_id" {
  value = aws_security_group.lambda_sg.id
}
