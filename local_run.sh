#!/bin/bash

# Default to local profile
PROFILE="local"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --aws) PROFILE="aws" ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

echo "------------------------------------------------"
echo "Starting Spring Boot with Profile: $PROFILE"
echo "------------------------------------------------"

if [ "$PROFILE" == "aws" ]; then
    # Ensure AWS_PROFILE is set
    if [ -z "$AWS_PROFILE" ]; then
        echo "Error: AWS_PROFILE must be set to use --aws mode."
        exit 1
    fi

    echo "Fetching infrastructure details from Terraform..."
    cd ../iac
    
    export DB_HOST=$(terraform output -raw rds_endpoint 2>/dev/null)
    export SECRET_ARN=$(terraform output -raw db_password_secret_arn 2>/dev/null)
    export AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
    
    if [ -z "$SECRET_ARN" ]; then
        echo "Error: Could not retrieve Secret ARN from Terraform."
        exit 1
    fi

    echo "Fetching DB Password from AWS Secrets Manager..."
    export DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text --profile "$AWS_PROFILE" --region "$AWS_REGION")
    
    cd ..
    
    SPRING_ARGS="-Dspring.profiles.active=aws -DDB_HOST=$DB_HOST -DDB_PASSWORD=$DB_PASSWORD -DAWS_REGION=$AWS_REGION"
else
    echo "Starting local dependencies (Postgres)..."
    docker compose up -d postgres
    
    SPRING_ARGS="-Dspring.profiles.active=local"
fi

mvn spring-boot:run -Dspring-boot.run.jvmArguments="$SPRING_ARGS"
