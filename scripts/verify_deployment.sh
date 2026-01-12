#!/bin/bash

# Validation function
validate_environment() {
    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "❌ Error: AWS CLI is required but not installed"
        echo "   Install AWS CLI: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: 'jq' is required but not installed"
        echo "   On Ubuntu/Debian: sudo apt-get install jq"
        echo "   On RHEL/CentOS: sudo yum install jq"
        echo "   On macOS: brew install jq"
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

# Configuration
REGION="${AWS_REGION:-us-east-1}"

# Retrieve configuration from Terraform
cd iac || exit

# Helper to get value from output or fallback to state file
get_val() {
    # Try getting from output first
    VAL=$(terraform output -raw "$1" 2>/dev/null)
    if [ -z "$VAL" ] || [[ "$VAL" == *"Warning"* ]]; then
        # Fallback: Extract directly from state file using jq
        case "$1" in
            "s3_bucket_name")
                VAL=$(jq -r '.resources[] | select(.type == "aws_s3_bucket") | .instances[0].attributes.id' terraform.tfstate 2>/dev/null)
                ;;
            "direct_message_queue_url")
                VAL=$(jq -r '.resources[] | select(.name == "direct_message_queue") | .instances[0].attributes.id' terraform.tfstate 2>/dev/null)
                ;;
            "aws_region")
                VAL=$(jq -r '.outputs.aws_region.value // empty' terraform.tfstate 2>/dev/null)
                ;;
        esac
    fi
    echo "$VAL"
}

echo "Retrieving infrastructure details..."
BUCKET_NAME=$(get_val "s3_bucket_name")
DIRECT_QUEUE_URL=$(get_val "direct_message_queue_url")
TF_REGION=$(get_val "aws_region")
REGION="${TF_REGION:-$REGION}"

cd ..

if [ -z "$BUCKET_NAME" ] || [ -z "$DIRECT_QUEUE_URL" ] || [[ "$BUCKET_NAME" == "null" ]]; then
    echo "------------------------------------------------"
    echo "Error: Could not retrieve infrastructure details."
    echo "Please rerun your deployment script once to update the Terraform state:"
    echo "  AWS_PROFILE=$AWS_PROFILE AWS_REGION=$REGION ./iac_create.sh"
    echo "------------------------------------------------"
    exit 1
fi

echo "------------------------------------------------"
echo "Microservice Verification Script"
echo "Region: $REGION"
echo "Bucket: $BUCKET_NAME"
echo "Queue:  $DIRECT_QUEUE_URL"
echo "------------------------------------------------"

# 1. Test Direct SQS Message
echo "1. Sending Test Message to Direct Queue..."
MESSAGE_BODY="Hello from Verification Script at $(date)"
aws sqs send-message \
  --queue-url "$DIRECT_QUEUE_URL" \
  --message-body "$MESSAGE_BODY" \
  --region "$REGION"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to send message to SQS queue"
    echo "   Queue URL: $DIRECT_QUEUE_URL"
    echo "   Region: $REGION"
    echo "   Troubleshooting:"
    echo "   - Verify IAM permissions for SQS (sqs:SendMessage)"
    echo "   - Check if queue exists: aws sqs list-queues --region $REGION"
    exit 1
fi
echo "✔️  Message sent successfully"

# 2. Test S3 Event
echo "2. Uploading Test File to S3..."
echo "This is some test content for the S3 event listener." > test.txt
aws s3 cp test.txt "s3://$BUCKET_NAME/test.txt" --region "$REGION"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to upload file to S3"
    echo "   Bucket: $BUCKET_NAME"
    echo "   Region: $REGION"
    echo "   Troubleshooting:"
    echo "   - Verify IAM permissions for S3 (s3:PutObject)"
    echo "   - Check if bucket exists: aws s3 ls s3://$BUCKET_NAME --region $REGION"
    exit 1
fi
rm test.txt
echo "✔️  File uploaded successfully"

echo "------------------------------------------------"
echo "Tests initiated successfully!"
echo "Check your ECS Task logs or RDS tables to verify results."
echo "Tables: 'direct_messages' and 's3_file_uploads'"
echo "------------------------------------------------"
