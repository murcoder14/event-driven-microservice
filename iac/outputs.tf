output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "s3_event_queue_url" {
  value = module.sqs.s3_event_queue_url
}

output "direct_message_queue_url" {
  value = module.sqs.direct_message_queue_url
}

output "rds_endpoint" {
  value = module.rds.db_endpoint
}

output "aws_region" {
  value = var.aws_region
}

output "master_password_secret_arn" {
  value = module.rds.master_password_secret_arn
}

output "tmpower_password_secret_arn" {
  value = module.rds.tmpower_password_secret_arn
}

output "tmapp_password_secret_arn" {
  value = module.rds.tmapp_password_secret_arn
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}
output "db_instance_identifier" {
  value = module.rds.db_instance_identifier
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
