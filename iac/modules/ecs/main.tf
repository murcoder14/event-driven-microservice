resource "aws_ecs_cluster" "main" {
  name = "event-driven-cluster"
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/event-driven-microservice"
  retention_in_days = 1
}

resource "aws_security_group" "ecs" {
  name        = "event-driven-ecs-sg"
  vpc_id      = var.vpc_id
  description = "Allow inbound traffic to ECS"
  revoke_rules_on_delete = true

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_task_execution_secrets" {
  name        = "ecs_task_execution_secrets"
  description = "Allows ECS Execution Role to fetch secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "secretsmanager:GetSecretValue"
        Effect   = "Allow"
        Resource = [
          var.master_password_secret_arn,
          var.tmpower_password_secret_arn,
          var.tmapp_password_secret_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_secrets.arn
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_task_policy" {
  name        = "ecs_task_policy"
  description = "Policy for ECS task to access S3 and SQS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/*"
        ]
      },
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:SendMessage",
          "sqs:CreateQueue"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "sqs:SendMessage"
        ]
        Effect   = "Allow"
        Resource = var.direct_message_dlq_arn
      },
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = [
          var.master_password_secret_arn,
          var.tmpower_password_secret_arn,
          var.tmapp_password_secret_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

resource "aws_ecs_task_definition" "app" {
  family                   = "event-driven-microservice"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "event-driven-container"
      image     = var.container_image
      essential = true
      
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      
      environment = [
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_USER", value = "tmapp" },
        { name = "FLYWAY_USER", value = "tmpower" },
        { name = "S3_EVENT_QUEUE", value = var.s3_event_queue_name },
        { name = "DIRECT_MESSAGE_QUEUE", value = var.direct_message_queue_name },
        { name = "DIRECT_MESSAGE_DLQ", value = var.direct_message_dlq_url },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "SPRING_PROFILES_ACTIVE", value = "aws" }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = var.tmapp_password_secret_arn
        },
        {
          name      = "FLYWAY_PASSWORD"
          valueFrom = var.tmpower_password_secret_arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/event-driven-microservice"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "main" {
  name            = "event-driven-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
}

variable "container_image" { type = string }
variable "db_host" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "s3_event_queue_name" { type = string }
variable "direct_message_queue_name" { type = string }
variable "direct_message_dlq_url" { type = string }
variable "direct_message_dlq_arn" { type = string }
variable "aws_region" { type = string }
variable "bucket_arn" { type = string }
variable "master_password_secret_arn" { type = string }
variable "tmpower_password_secret_arn" { type = string }
variable "tmapp_password_secret_arn" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}
