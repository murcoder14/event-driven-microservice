provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source     = "./modules/vpc"
  aws_region = var.aws_region
}

module "ecr" {
  source = "./modules/ecr"
}

module "s3" {
  source      = "./modules/s3"
  bucket_name = var.bucket_name
}

module "sqs" {
  source                    = "./modules/sqs"
  s3_event_queue_name       = "s3-event-queue"
  direct_message_queue_name = "direct-message-queue"
}

module "rds" {
  source            = "./modules/rds"
  db_name           = "event_db"
  db_username       = var.db_username
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnets
  allowed_mgmt_cidr = var.allowed_mgmt_cidr
}

module "ecs" {
  source                      = "./modules/ecs"
  container_image             = var.container_image == "event-driven-microservice:latest" ? "${module.ecr.repository_url}:latest" : var.container_image
  db_host                     = module.rds.db_endpoint
  db_name                     = "event_db"
  db_user                     = var.db_username
  master_password_secret_arn  = module.rds.master_password_secret_arn
  tmpower_password_secret_arn = module.rds.tmpower_password_secret_arn
  tmapp_password_secret_arn   = module.rds.tmapp_password_secret_arn
  s3_event_queue_name         = "s3-event-queue"
  direct_message_queue_name   = "direct-message-queue.fifo"
  direct_message_dlq_url      = module.sqs.direct_message_dlq_url
  direct_message_dlq_arn      = module.sqs.direct_message_dlq_arn
  aws_region                  = var.aws_region
  bucket_arn                  = module.s3.bucket_arn
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = module.vpc.public_subnets
}

module "db_bootstrap" {
  source             = "./modules/db_bootstrap"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  db_host            = module.rds.db_endpoint
  db_name            = "event_db"
  master_secret_arn  = module.rds.master_password_secret_arn
  tmpower_secret_arn = module.rds.tmpower_password_secret_arn
  tmapp_secret_arn   = module.rds.tmapp_password_secret_arn

  depends_on = [module.rds]
}

module "cloudwatch" {
  source         = "./modules/cloudwatch"
  dlq_name       = "direct-message-queue-dlq.fifo"
  queue_name     = "direct-message-queue.fifo"
  cluster_name   = "event-driven-cluster"
  service_name   = "event-driven-service"
  log_group_name = "/ecs/event-driven-microservice"

  depends_on = [module.ecs, module.sqs]
}

# ============================================================================
# ELITE BRIDGES: Breaking Circular Dependencies
# ============================================================================

# 1. RDS & ECS Firewall Rule
resource "aws_security_group_rule" "ecs_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_security_group_id
  source_security_group_id = module.ecs.ecs_security_group_id
}

# 2. RDS & Lambda Firewall Rule
resource "aws_security_group_rule" "lambda_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_security_group_id
  source_security_group_id = module.db_bootstrap.lambda_security_group_id
}

# 3. RDS & Management Firewall Rule (Laptop Access)
resource "aws_security_group_rule" "mgmt_to_rds" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = module.rds.rds_security_group_id
  cidr_blocks       = [var.allowed_mgmt_cidr]
}

# 4. SQS Queue Policy (Allows S3 Notifications)
resource "aws_sqs_queue_policy" "s3_event_queue_policy" {
  queue_url = module.sqs.s3_event_queue_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = module.sqs.s3_event_queue_arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = module.s3.bucket_arn
          }
        }
      }
    ]
  })
}

# 4. S3 Bucket Notification (Triggers SQS)
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.s3.bucket_id

  queue {
    queue_arn     = module.sqs.s3_event_queue_arn
    events        = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.s3_event_queue_policy]
}
