# Terraform Backend Configuration for S3
# 
# To use this backend:
# 1. Create an S3 bucket for state storage
# 2. Create a DynamoDB table for state locking
# 3. Uncomment the terraform block below
# 4. Run: terraform init -migrate-state
#
# Example AWS CLI commands to create resources:
#
# aws s3api create-bucket \
#   --bucket your-terraform-state-bucket \
#   --region us-east-1
#
# aws s3api put-bucket-versioning \
#   --bucket your-terraform-state-bucket \
#   --versioning-configuration Status=Enabled
#
# aws s3api put-bucket-encryption \
#   --bucket your-terraform-state-bucket \
#   --server-side-encryption-configuration '{
#     "Rules": [{
#       "ApplyServerSideEncryptionByDefault": {
#         "SSEAlgorithm": "AES256"
#       }
#     }]
#   }'
#
# aws dynamodb create-table \
#   --table-name terraform-state-lock \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST \
#   --region us-east-1

# Uncomment and configure after creating S3 bucket and DynamoDB table
# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "event-driven-microservice/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }
