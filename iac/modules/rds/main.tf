resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "tmpower_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "tmapp_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "event-driven-master-password-${random_id.id.hex}"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_secretsmanager_secret" "tmpower_password" {
  name = "event-driven-tmpower-password-${random_id.id.hex}"
}

resource "aws_secretsmanager_secret_version" "tmpower_password" {
  secret_id     = aws_secretsmanager_secret.tmpower_password.id
  secret_string = random_password.tmpower_password.result
}

resource "aws_secretsmanager_secret" "tmapp_password" {
  name = "event-driven-tmapp-password-${random_id.id.hex}"
}

resource "aws_secretsmanager_secret_version" "tmapp_password" {
  secret_id     = aws_secretsmanager_secret.tmapp_password.id
  secret_string = random_password.tmapp_password.result
}

resource "random_id" "id" {
  byte_length = 4
}

resource "aws_db_subnet_group" "rds" {
  name       = "event-driven-rds-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "Event Driven RDS Subnet Group"
  }
}

resource "aws_security_group" "rds" {
  name        = "event-driven-rds-sg"
  vpc_id      = var.vpc_id
  description = "Allow inbound traffic to RDS"
  revoke_rules_on_delete = true

  # NOTE: All ingress rules are managed via aws_security_group_rule 
  # resources in main.tf to avoid conflicts and circular dependencies.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "18"
  instance_class         = "db.t4g.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  parameter_group_name   = "default.postgres18"
  skip_final_snapshot    = true
  publicly_accessible    = true
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
}

variable "db_name" { type = string }
variable "db_username" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "allowed_mgmt_cidr" { type = string }

output "db_endpoint" {
  value = aws_db_instance.postgres.address
}

output "master_password_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "tmpower_password_secret_arn" {
  value = aws_secretsmanager_secret.tmpower_password.arn
}

output "tmapp_password_secret_arn" {
  value = aws_secretsmanager_secret.tmapp_password.arn
}

output "db_instance_identifier" {
  value = aws_db_instance.postgres.identifier
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

# Secrets Manager Rotation Configuration
# Note: Automatic rotation requires a Lambda function to perform the rotation
# For PostgreSQL RDS, AWS provides a managed rotation Lambda

resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = 30
  }

  # Only enable if rotation Lambda is provided
  count = var.enable_rotation ? 1 : 0
}

resource "aws_secretsmanager_secret_rotation" "tmpower_password" {
  secret_id           = aws_secretsmanager_secret.tmpower_password.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = 30
  }

  count = var.enable_rotation ? 1 : 0
}

resource "aws_secretsmanager_secret_rotation" "tmapp_password" {
  secret_id           = aws_secretsmanager_secret.tmapp_password.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = 30
  }

  count = var.enable_rotation ? 1 : 0
}

variable "enable_rotation" {
  type    = bool
  default = false
  description = "Enable automatic password rotation (requires rotation_lambda_arn)"
}

variable "rotation_lambda_arn" {
  type    = string
  default = ""
  description = "ARN of Lambda function for password rotation"
}
