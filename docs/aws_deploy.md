# AWS Deployment Guide

This guide provides detailed steps for deploying the event-driven microservice to AWS ECS Fargate.

---

## Prerequisites

- **AWS CLI** configured with credentials
- **Terraform 1.5+** installed
- **Docker** installed and running
- **Maven 3.9+** and **Java 25** for local builds

---

## Phase 1: Infrastructure Setup

This creates the ECR repository, VPC, RDS instance, S3 bucket, SQS queues, and ECS cluster.

### 1. Configure Environment Variables

Create or update `iac/terraform.tfvars`:

```hcl
aws_region        = "us-east-1"
bucket_name       = "your-unique-bucket-name"
allowed_mgmt_cidr = "your.public.ip.address/32"
```

### 2. Set AWS Profile

```bash
export AWS_PROFILE=your-profile-name
```

### 3. Create Infrastructure

```bash
./scripts/iac_create.sh
```

This script:
- Initializes Terraform
- Creates ECR repository
- Pushes placeholder image
- Deploys full infrastructure
- Triggers automated database bootstrapping via Lambda

---

## Phase 2: Automated Database Bootstrapping

The infrastructure uses **Zero-Touch Provisioning**. An AWS Lambda function automatically:

1. Connects to RDS inside the VPC
2. Fetches passwords from Secrets Manager
3. Initializes `tmschema` and RBAC roles (`tmpower`, `tmapp`)
4. Configures `search_path` and `DEFAULT PRIVILEGES`

> **Note:** No manual SQL execution required. The system is ready immediately after Terraform completes.

---

## Phase 3: Deploy Application

Once infrastructure exists, deploy the application code:

```bash
./scripts/cicd.sh
```

This script:
- Builds application with Maven
- Creates container image with Jib
- Pushes to ECR
- Scans for vulnerabilities with Trivy
- Updates ECS service with new image
- Waits for deployment to stabilize

---

## Phase 4: Verification

### Test S3 Event Pipeline

```bash
echo "Cloud Integration Test" > sample.txt
BUCKET_NAME=$(terraform -chdir=iac output -raw s3_bucket_name)

# Upload file
aws s3 cp sample.txt s3://$BUCKET_NAME/sample.txt

# Verify event reached queue
S3_QUEUE_URL=$(terraform -chdir=iac output -raw s3_event_queue_url)
aws sqs get-queue-attributes --queue-url $S3_QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages
```

### Test Direct Message Pipeline

```bash
DM_QUEUE_URL=$(terraform -chdir=iac output -raw direct_message_queue_url)

# Send message
aws sqs send-message --queue-url $DM_QUEUE_URL \
  --message-body '{"city":"Seattle","country":"USA","messageId":"test-123"}'

# Check queue depth
aws sqs get-queue-attributes --queue-url $DM_QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages
```

### Query Production Database

```bash
# Get credentials
SECRET_ARN=$(terraform -chdir=iac output -raw tmpower_password_secret_arn)
PASSWD=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN \
  --query SecretString --output text)
RDS_HOST=$(terraform -chdir=iac output -raw rds_endpoint)

# Query database
PGPASSWORD=$PASSWD psql -h $RDS_HOST -U tmpower -d event_db \
  -c "SELECT * FROM direct_messages;"
```

---

## Monitoring

### View Logs

```bash
# Tail logs
aws logs tail /ecs/event-driven-microservice --follow

# Filter errors
aws logs tail /ecs/event-driven-microservice --follow --filter-pattern "ERROR"
```

### Check Health

```bash
# Get ECS task public IP
TASK_ARN=$(aws ecs list-tasks --cluster event-driven-cluster \
  --service-name event-driven-service --query 'taskArns[0]' --output text)

TASK_IP=$(aws ecs describe-tasks --cluster event-driven-cluster \
  --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text | xargs -I {} aws ec2 describe-network-interfaces \
  --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

# Check health
curl http://$TASK_IP:8080/actuator/health
```

### CloudWatch Alarms

Monitor alarms in AWS Console:
- **CloudWatch → Alarms**
- Filter by prefix: `event-driven-`

---

## Cleanup

### Data Cleanup (Keep Infrastructure)

```bash
# Empty S3 bucket
BUCKET_NAME=$(terraform -chdir=iac output -raw s3_bucket_name)
aws s3 rm s3://$BUCKET_NAME --recursive

# Purge queues
S3_QUEUE_URL=$(terraform -chdir=iac output -raw s3_event_queue_url)
DM_QUEUE_URL=$(terraform -chdir=iac output -raw direct_message_queue_url)
aws sqs purge-queue --queue-url $S3_QUEUE_URL
aws sqs purge-queue --queue-url $DM_QUEUE_URL
```

### Full Teardown

Using [cloud-nuke](https://github.com/gruntwork-io/cloud-nuke) for complete cleanup:

```bash
# Nuke all resources
cloud-nuke aws --region us-east-1

# Clear local Terraform state
cd iac
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
```

---

## Troubleshooting

### ECS Task Won't Start

```bash
# Check task status
aws ecs describe-tasks --cluster event-driven-cluster \
  --tasks $(aws ecs list-tasks --cluster event-driven-cluster \
  --service-name event-driven-service --query 'taskArns[0]' --output text)

# Check stopped tasks
aws ecs list-tasks --cluster event-driven-cluster \
  --desired-status STOPPED --max-results 5
```

### Database Connection Issues

```bash
# Verify RDS status
aws rds describe-db-instances --db-instance-identifier event-driven-db

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=event-driven-*"
```

### Queue Not Processing

```bash
# Check DLQ depth
DLQ_URL=$(terraform -chdir=iac output -raw direct_message_dlq_url)
aws sqs get-queue-attributes --queue-url $DLQ_URL \
  --attribute-names ApproximateNumberOfMessages

# Check circuit breaker state
curl http://$TASK_IP:8080/actuator/metrics/resilience4j.circuitbreaker.state
```

---

## Advanced Configuration

### Enable Secrets Rotation

1. Deploy AWS-provided rotation Lambda for PostgreSQL
2. Update `iac/terraform.tfvars`:
   ```hcl
   enable_rotation = true
   rotation_lambda_arn = "arn:aws:lambda:..."
   ```
3. Apply changes: `terraform apply`

### Configure Remote State

1. Create S3 bucket and DynamoDB table (see `iac/backend.tf`)
2. Uncomment backend configuration in `iac/backend.tf`
3. Run: `terraform init -migrate-state`

### Scale ECS Service

```bash
aws ecs update-service --cluster event-driven-cluster \
  --service event-driven-service --desired-count 3
```

---

## Security Best Practices

- ✅ Use IAM roles for ECS tasks (no hardcoded credentials)
- ✅ Store secrets in Secrets Manager
- ✅ Enable rotation for database passwords
- ✅ Use VPC isolation for RDS
- ✅ Restrict security groups to minimum required access
- ✅ Enable CloudWatch alarms for security events
- ✅ Scan containers for vulnerabilities before deployment

---

For more details, see:
- [Architecture Overview](architecture.md)
- [FAQ](faq.md)
- [Main README](../README.md)
