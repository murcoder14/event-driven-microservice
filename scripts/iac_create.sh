#!/bin/bash
set -e

# Validation function for required environment variables
validate_environment() {
    local missing_vars=()
    
    # Check for AWS credentials
    if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_PROFILE" ]; then
        missing_vars+=("AWS_ACCESS_KEY_ID or AWS_PROFILE")
    fi
    
    if [ -z "$AWS_SECRET_ACCESS_KEY" ] && [ -z "$AWS_PROFILE" ]; then
        missing_vars+=("AWS_SECRET_ACCESS_KEY or AWS_PROFILE")
    fi
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        echo "❌ Error: Docker is required but not installed"
        echo "   Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker ps &> /dev/null; then
        echo "❌ Error: Docker daemon is not running"
        echo "   Start Docker and try again"
        exit 1
    fi
    
    # Check for Terraform
    if ! command -v terraform &> /dev/null; then
        echo "❌ Error: Terraform is required but not installed"
        echo "   Install Terraform: https://www.terraform.io/downloads"
        exit 1
    fi
    
    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "❌ Error: AWS CLI is required but not installed"
        echo "   Install AWS CLI: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "❌ Error: Required environment variables not set:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo ""
        echo "   Set AWS credentials using one of these methods:"
        echo "   1. AWS Profile: export AWS_PROFILE=your-profile"
        echo "   2. Access Keys: export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."
        echo "   3. AWS SSO: aws sso login --profile your-profile"
        exit 1
    fi
    
    # Verify AWS credentials work
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ Error: AWS credentials are invalid or expired"
        echo "   Profile: ${AWS_PROFILE:-default}"
        echo "   Region: ${AWS_REGION:-us-east-1}"
        echo "   Troubleshooting:"
        echo "   - Run: aws sts get-caller-identity"
        echo "   - Check credentials: aws configure list"
        echo "   - For SSO: aws sso login --profile $AWS_PROFILE"
        exit 1
    fi
}

# Run validation
echo "🔍 Validating environment..."
validate_environment
echo "✔️  Environment validation passed"
echo ""

# Configuration - can be overridden by environment variables
REGION="${AWS_REGION:-us-east-1}"
PROFILE_ARG=""
if [ -n "$AWS_PROFILE" ]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# 1. Sticky Bucket Logic: Try to reuse existing bucket if it exists in terraform outputs
EXISTING_BUCKET=$(terraform -chdir=iac output -raw s3_bucket_name 2>/dev/null || echo "")

# Validate: Must be non-empty, not an error message, and look like a bucket name
# If validation fails, we generate a fresh name.
if [[ "$EXISTING_BUCKET" =~ ^muralis-event-bucket-[0-9]+$ ]]; then
    BUCKET_NAME="${BUCKET_NAME:-$EXISTING_BUCKET}"
    echo "♻️  Reusing existing S3 bucket: $BUCKET_NAME"
else
    # Fallback to generating a new name if state is empty or invalid
    BUCKET_NAME="${BUCKET_NAME:-muralis-event-bucket-$(date +%s)}"
    echo "🆕 Generating new S3 bucket name: $BUCKET_NAME"
fi

IMAGE_URI="${IMAGE_URI:-public.ecr.aws/docker/library/nginx:latest}"
ALLOWED_MGMT_CIDR="${ALLOWED_MGMT_CIDR:-0.0.0.0/32}"

# Status Update
echo "------------------------------------------------"
if [ -z "$AWS_PROFILE" ]; then
    echo "AWS Profile: [DEFAULT]"
else
    echo "AWS Profile: $AWS_PROFILE"
fi
echo "AWS Region:  $REGION"
echo "Management CIDR: $ALLOWED_MGMT_CIDR"
echo "------------------------------------------------"

cd iac

echo "Initializing Terraform..."
terraform init

if [ $? -ne 0 ]; then
    echo "❌ Error: Terraform initialization failed"
    echo "   Troubleshooting:"
    echo "   - Check your AWS credentials: aws sts get-caller-identity"
    echo "   - Verify Terraform is installed: terraform version"
    echo "   - Check network connectivity to Terraform registry"
    exit 1
fi

echo "🏗️  Step 1: Provisioning ECR Repository..."
terraform apply -auto-approve -target=module.ecr -var="container_image=placeholder"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to provision ECR repository"
    echo "   Troubleshooting:"
    echo "   - Check AWS credentials: aws sts get-caller-identity"
    echo "   - Verify IAM permissions for ECR (ecr:CreateRepository, ecr:DescribeRepositories)"
    echo "   - Check if ECR repository already exists in AWS Console"
    exit 1
fi

ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
REGION=$(terraform output -raw aws_region 2>/dev/null || echo "$REGION")

if [ -z "$ECR_REPO_URL" ]; then
    echo "❌ Error: Could not retrieve ECR repository URL from Terraform output"
    echo "   This usually means the ECR module failed to create the repository"
    exit 1
fi

echo "🔑 Authenticating with ECR..."
aws ecr get-login-password --region "$REGION" $PROFILE_ARG | docker login --username AWS --password-stdin "$ECR_REPO_URL"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to authenticate with ECR"
    echo "   Region: $REGION"
    echo "   Profile: ${AWS_PROFILE:-default}"
    echo "   Troubleshooting:"
    echo "   - Verify AWS credentials: aws sts get-caller-identity"
    echo "   - Check Docker is running: docker ps"
    echo "   - Verify IAM permissions for ECR (ecr:GetAuthorizationToken)"
    exit 1
fi

echo "📦 Creating and pushing placeholder image to ECR..."
# Build a minimal placeholder image from scratch to avoid multi-arch issues
# Using nginx:alpine which is simpler and avoids manifest list complications
docker pull nginx:alpine

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to pull nginx:alpine image"
    echo "   Troubleshooting:"
    echo "   - Check Docker is running: docker ps"
    echo "   - Check internet connectivity"
    echo "   - Try: docker pull nginx:alpine manually"
    exit 1
fi

docker tag nginx:alpine "$ECR_REPO_URL:placeholder"
docker push "$ECR_REPO_URL:placeholder"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to push placeholder image to ECR"
    echo "   ECR URL: $ECR_REPO_URL:placeholder"
    echo "   Troubleshooting:"
    echo "   - Verify ECR authentication is still valid"
    echo "   - Check IAM permissions for ECR (ecr:PutImage, ecr:InitiateLayerUpload)"
    echo "   - Check network connectivity to ECR"
    exit 1
fi

echo "🚀 Step 2: Applying Full Terraform Infrastructure..."
terraform apply -auto-approve \
  -var="container_image=$ECR_REPO_URL:placeholder"

if [ $? -ne 0 ]; then
    echo "❌ Error: Terraform apply failed"
    echo "   Troubleshooting:"
    echo "   - Review Terraform error messages above"
    echo "   - Check AWS service quotas (VPC, ECS, RDS, etc.)"
    echo "   - Verify IAM permissions for all required services"
    echo "   - Check if resources already exist with conflicting names"
    echo "   - Try: terraform plan to see what would be created"
    exit 1
fi

# CRITICAL: Force a sync of the "Elite Bridge" rules which often drift
echo "🔄 Verifying and syncing Security Group bridges..."
terraform apply -auto-approve \
  -target=aws_security_group_rule.ecs_to_rds \
  -target=aws_security_group_rule.lambda_to_rds \
  -target=aws_security_group_rule.mgmt_to_rds \
  -var="container_image=$ECR_REPO_URL:placeholder"

echo "✔️  Infrastructure creation and verification completed."
