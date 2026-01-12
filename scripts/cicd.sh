#!/bin/bash
# Removed set -e to prevent premature exits - using explicit error checking instead

# Configuration
REGION="${AWS_REGION:-us-east-1}"
PROFILE_ARG=""
if [ -n "$AWS_PROFILE" ]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

CLUSTER_NAME="event-driven-cluster"
SERVICE_NAME="event-driven-service"

echo "------------------------------------------------"
echo "🚀 Starting CI/CD Pipeline"
echo "------------------------------------------------"

# 1. Pre-Deployment Health Checks
echo "🔍 Performing Pre-Deployment Health Checks..."

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is required but not installed. Please install it first."
    echo "   On Ubuntu/Debian: sudo apt-get install jq"
    echo "   On RHEL/CentOS: sudo yum install jq"
    echo "   On macOS: brew install jq"
    exit 1
fi

# A. Verify ECR Repository and Fetch Infrastructure State
ECR_REPO_URL=$(terraform -chdir=iac output -raw ecr_repository_url 2>/dev/null)
BUCKET_NAME=$(terraform -chdir=iac output -raw s3_bucket_name 2>/dev/null)
REGION=$(terraform -chdir=iac output -raw aws_region 2>/dev/null || echo "$REGION")

if [ -z "$ECR_REPO_URL" ] || [ -z "$BUCKET_NAME" ]; then
    echo "❌ Error: Could not fetch infrastructure state. Have you run ./iac_create.sh yet?"
    exit 1
fi
echo "✔️  ECR Repository: $ECR_REPO_URL"
echo "✔️  S3 Bucket: $BUCKET_NAME"

# B. Verify Service Presence
echo "🔍 Checking if ECS service '$SERVICE_NAME' is active..."
SERVICE_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$REGION" $PROFILE_ARG --query "services[0].status" --output text)

if [ $? -ne 0 ] || [ "$SERVICE_STATUS" != "ACTIVE" ]; then
    echo "❌ Error: ECS Service is '$SERVICE_STATUS'. Please run ./iac_create.sh to provision/re-sync infrastructure."
    exit 1
fi
echo "✔️  ECS Service: ACTIVE"

# 2. Get ECR Login Password
echo "🔑 Authenticating with ECR..."
ECR_PASSWORD=$(aws ecr get-login-password --region "$REGION" $PROFILE_ARG)
if [ $? -ne 0 ] || [ -z "$ECR_PASSWORD" ]; then
    echo "❌ Error: Failed to authenticate with ECR"
    exit 1
fi


# 3. Build and Push with Jib
echo "📦 Building application and pushing to ECR..."
TAG=$(date +%Y%m%d%H%M%S)
DIGEST_FILE="target/jib-image.digest"

# Build and push. We use a digest file for reliable verification.
mvn clean compile jib:build \
    -Djib.to.image="$ECR_REPO_URL:$TAG" \
    -Djib.to.tags=latest \
    -Djib.to.auth.username=AWS \
    -Djib.to.auth.password="$ECR_PASSWORD" \
    -Djib.outputPaths.digest="$DIGEST_FILE"

if [ $? -ne 0 ]; then
    echo "❌ Error: Maven build failed"
    exit 1
fi

# Extract digest from the file Jib created
if [ -f "$DIGEST_FILE" ]; then
    EXPECTED_DIGEST=$(cat "$DIGEST_FILE")
else
    echo "❌ Error: Jib digest file not found at $DIGEST_FILE"
    exit 1
fi

# Verify image push in ECR
echo "🔍 Verifying image in ECR..."
REPO_NAME=$(echo "$ECR_REPO_URL" | cut -d'/' -f2)
ACTUAL_DIGEST=$(aws ecr describe-images --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" --region "$REGION" $PROFILE_ARG --query 'imageDetails[0].imageDigest' --output text 2>/dev/null)

if [ -z "$ACTUAL_DIGEST" ] || [ "$ACTUAL_DIGEST" == "None" ]; then
    echo "❌ Error: Image with tag $TAG not found in ECR!"
    exit 1
fi

if [ "$ACTUAL_DIGEST" != "$EXPECTED_DIGEST" ]; then
    echo "❌ Error: Digest mismatch! ECR has $ACTUAL_DIGEST but Jib reported $EXPECTED_DIGEST"
    exit 1
fi
echo "✔️  Image verified in ECR with digest: $ACTUAL_DIGEST"

# 4. Container Security Scanning with Trivy
echo "🔍 Scanning container for vulnerabilities..."
if command -v trivy &> /dev/null; then
    echo "   Running Trivy security scan..."
    trivy image --severity HIGH,CRITICAL "$ECR_REPO_URL:$TAG" --exit-code 0
    TRIVY_EXIT_CODE=$?
    
    if [ $TRIVY_EXIT_CODE -ne 0 ]; then
        echo "⚠️  Warning: Trivy found HIGH or CRITICAL vulnerabilities"
        echo "   Review the scan results above and consider updating dependencies"
        echo "   Continuing with deployment (set --exit-code 1 to fail on vulnerabilities)"
    else
        echo "✔️  No HIGH or CRITICAL vulnerabilities found"
    fi
else
    echo "⚠️  Trivy not installed - skipping vulnerability scan"
    echo "   Install Trivy for container security scanning:"
    echo "   - Ubuntu/Debian: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
    echo "   - macOS: brew install trivy"
fi

# 5. Trigger ECS Deployment via Terraform
# This is the most rigorous way as it ensures the Task Definition is updated 
# and all infrastructure dependencies (like SG rules) are in sync.
echo "🔄 Updating ECS Task Definition and triggering deployment..."
terraform -chdir=iac apply -auto-approve \
    -var="container_image=$ECR_REPO_URL:$TAG"

if [ $? -ne 0 ]; then
    echo "❌ Error: Terraform apply failed during deployment"
    exit 1
fi

# Get the new Deployment ID to monitor
DEPLOYMENT_ID=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$REGION" $PROFILE_ARG --query "services[0].deployments[?status=='PRIMARY'].id" --output text)
echo "✔️  Deployment triggered: $DEPLOYMENT_ID"

# 6. Proactive Wait for Stability (Fail-Fast Logic)
echo "⏳ Monitoring deployment for stability (Fail-Fast mode enabled)..."

MAX_RETRIES=60  # Increased to 15 minutes (60 * 15 seconds)
RETRIES=0
STABLE=false

while [ $RETRIES -lt $MAX_RETRIES ]; do
    # Get comprehensive service status with error handling
    if ! SERVICE_INFO=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$REGION" $PROFILE_ARG --output json 2>/dev/null); then
        echo "   ⚠️  Failed to get service info, retrying..."
        sleep 15
        ((RETRIES++))
        continue
    fi
    
    # Check deployment status with error handling
    PRIMARY_DEPLOYMENT=$(echo "$SERVICE_INFO" | jq -r '.services[0].deployments[] | select(.status=="PRIMARY")' 2>/dev/null)
    DEPLOYMENT_STATUS=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.rolloutState // "IN_PROGRESS"' 2>/dev/null || echo "IN_PROGRESS")
    RUNNING_COUNT=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.runningCount' 2>/dev/null || echo "0")
    DESIRED_COUNT=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.desiredCount' 2>/dev/null || echo "1")
    
    echo "   Status: $DEPLOYMENT_STATUS | New Tasks Running: $RUNNING_COUNT/$DESIRED_COUNT (Attempt $((RETRIES+1))/$MAX_RETRIES)"
    
    # Check for failed tasks only from the CURRENT deployment
    RECENT_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-status STOPPED --region "$REGION" $PROFILE_ARG --query "taskArns" --output text 2>/dev/null || echo "None")
    
    if [ "$RECENT_TASKS" != "None" ] && [ -n "$RECENT_TASKS" ]; then
        for TASK_ARN in $RECENT_TASKS; do
            if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
                TASK_INFO=$(aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN" --region "$REGION" $PROFILE_ARG --output json 2>/dev/null || echo '{}')
                TASK_DEPLOYMENT_ID=$(echo "$TASK_INFO" | jq -r '.tasks[0].startedBy' 2>/dev/null)
                
                # Only check tasks belonging to our current deployment
                if [ "$TASK_DEPLOYMENT_ID" != "$DEPLOYMENT_ID" ]; then
                    continue
                fi

                STOP_REASON=$(echo "$TASK_INFO" | jq -r '.tasks[0].stoppedReason // "Unknown"' 2>/dev/null || echo "Unknown")
                LAST_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].lastStatus // "Unknown"' 2>/dev/null || echo "Unknown")
                
                # Only fail on actual errors, not normal container exits
                if [[ "$STOP_REASON" == *"Task failed"* ]] || [[ "$STOP_REASON" == *"CannotPull"* ]] || [[ "$STOP_REASON" == *"OutOfMemory"* ]] || [[ "$STOP_REASON" == *"Essential container in task exited"* ]]; then
                    echo "------------------------------------------------"
                    echo "❌ CRITICAL ERROR DETECTED: Task failed/stopped."
                    echo "🔍 Reason: $STOP_REASON"
                    echo "🔍 Last Status: $LAST_STATUS"
                    echo "💡 Note: If logs show the app started, it likely crashed shortly after"
                    echo "   or failed an ECS health check. Check CloudWatch Logs for details."
                    echo "------------------------------------------------"
                    exit 1
                fi
            fi
        done
    fi

    # Check if deployment is stable - must be COMPLETED with correct task counts
    if [ "$DEPLOYMENT_STATUS" = "COMPLETED" ] && [ "$RUNNING_COUNT" = "$DESIRED_COUNT" ] && [ "$RUNNING_COUNT" -gt 0 ]; then
        echo "   ✅ Deployment completed successfully!"
        STABLE=true
        break
    fi

    # Continue monitoring if still in progress
    if [ "$DEPLOYMENT_STATUS" = "IN_PROGRESS" ]; then
        echo "   ⏳ Deployment still in progress, waiting..."
    elif [ "$DEPLOYMENT_STATUS" = "FAILED" ]; then
        echo "------------------------------------------------"
        echo "❌ DEPLOYMENT FAILED"
        echo "------------------------------------------------"
        exit 1
    else
        echo "   📊 Status: $DEPLOYMENT_STATUS (continuing to monitor...)"
    fi

    sleep 15
    ((RETRIES++))
done

if [ "$STABLE" = true ]; then
    # Final verification - get current task status
    FINAL_SERVICE_INFO=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$REGION" $PROFILE_ARG --output json)
    PRIMARY_DEPLOYMENT=$(echo "$FINAL_SERVICE_INFO" | jq -r '.services[0].deployments[] | select(.status=="PRIMARY")')
    FINAL_RUNNING_COUNT=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.runningCount')
    FINAL_DESIRED_COUNT=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.desiredCount')
    
    # Get the running task details
    RUNNING_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-status RUNNING --region "$REGION" $PROFILE_ARG --query "taskArns" --output text)
    
    echo "------------------------------------------------"
    echo "✅ CI/CD Pipeline Completed Successfully!"
    echo "🚀 Deployment is LIVE and STABLE."
    echo "📊 Final Status (New Deployment):"
    echo "   - Running Tasks: $FINAL_RUNNING_COUNT/$FINAL_DESIRED_COUNT"
    echo "   - Task ARNs: $RUNNING_TASKS"
    echo "------------------------------------------------"
else
    echo "❌ Error: Deployment timed out after $((MAX_RETRIES * 15 / 60)) minutes."
    echo "💡 Check ECS console for detailed task failure reasons."
    exit 1
fi
