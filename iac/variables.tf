variable "aws_region" {
  default = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "db_username" {
  default = "postgres"
}


variable "container_image" {
  description = "The image URI for the ECS task"
  type        = string
}

variable "allowed_mgmt_cidr" {
  description = "CIDR block allowed to manage the database remotely"
  type        = string
  default     = "0.0.0.0/32" # Safe default (nobody)
}
