# Local Development Guide

This guide explains how to run the event-driven microservice locally using **LocalStack** and **Docker Compose**.

---

## Prerequisites

- **Docker** and **Docker Compose** installed
- **AWS CLI** installed
- **Java 25** and **Maven 3.9+**
- **PostgreSQL client** (psql) for database access

---

## Environment Setup

### Set AWS Profile

Always set your AWS profile before starting:

```bash
export AWS_PROFILE=your-profile-name
```

> **Note:** This is required even for local development because the AWS SDK needs credentials (LocalStack doesn't validate them).

---

## Step 1: Start Dependencies

Start LocalStack (AWS emulation) and PostgreSQL:

```bash
docker-compose up -d
```

This starts:
- **PostgreSQL 18** on port `5434`
- **LocalStack** on port `4566` (S3, SQS)

### Verify Services

```bash
# Check containers
docker-compose ps

# Check LocalStack health
curl http://localhost:4566/_localstack/health
```

---

## Step 2: Bootstrap Database

### Create Schema and Users

```bash
psql -h localhost -p 5434 -U postgres -d event_db -f scripts/db_setup.sql
```

Password: `password`

This creates:
- Schema: `tmschema`
- Users: `tmpower` (migrations), `tmdev` (application)
- Tables: `direct_messages`, `s3_file_uploads`

### Verify Database

```bash
psql -h localhost -p 5434 -U tmdev -d event_db
# Password: dev_password

\dt tmschema.*
\q
```

---

## Step 3: Create LocalStack Resources

### Create SQS Queues

```bash
# S3 event queue
aws --endpoint-url=http://localhost:4566 sqs create-queue \
  --queue-name s3-event-queue

# Direct message queue
aws --endpoint-url=http://localhost:4566 sqs create-queue \
  --queue-name direct-message-queue
```

### Create S3 Bucket

```bash
aws --endpoint-url=http://localhost:4566 s3 mb s3://muralis-event-bucket-local
```

### Configure S3 Event Notifications

```bash
aws --endpoint-url=http://localhost:4566 s3api put-bucket-notification-configuration \
  --bucket muralis-event-bucket-local \
  --notification-configuration '{
    "QueueConfigurations": [{
      "QueueArn": "arn:aws:sqs:us-east-1:000000000000:s3-event-queue",
      "Events": ["s3:ObjectCreated:*"]
    }]
  }'
```

### Verify Resources

```bash
# List queues
aws --endpoint-url=http://localhost:4566 sqs list-queues

# List buckets
aws --endpoint-url=http://localhost:4566 s3 ls
```

---

## Step 4: Run Application

### Using the Script

```bash
./local_run.sh
```

This runs the application with the `local` profile, which:
- Connects to LocalStack (port 4566)
- Connects to PostgreSQL (port 5434)
- Uses plain text logging (not JSON)

### Manual Run

```bash
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

### Verify Application

```bash
# Check health
curl http://localhost:8080/actuator/health

# Check metrics
curl http://localhost:8080/actuator/metrics

# View API docs
open http://localhost:8080/swagger-ui.html
```

---

## Step 5: Test the System

### Test Direct Message Pipeline

```bash
aws --endpoint-url=http://localhost:4566 sqs send-message \
  --queue-url http://localhost:4566/000000000000/direct-message-queue \
  --message-body '{"city":"Seattle","country":"USA","messageId":"local-test-123"}'
```

Expected behavior:
1. Application receives message from SQS
2. Calls Open-Meteo API for weather data
3. Saves to `direct_messages` table
4. Acknowledges message (removes from queue)

### Test S3 Event Pipeline

```bash
echo "Hello LocalStack" > test.txt
aws --endpoint-url=http://localhost:4566 s3 cp test.txt \
  s3://muralis-event-bucket-local/test.txt
```

Expected behavior:
1. S3 sends event to `s3-event-queue`
2. Application receives event
3. Downloads file from S3
4. Saves metadata to `s3_file_uploads` table

### Verify Database

```bash
psql -h localhost -p 5434 -U tmdev -d event_db

-- Check direct messages
SELECT * FROM tmschema.direct_messages;

-- Check S3 uploads
SELECT * FROM tmschema.s3_file_uploads;

\q
```

---

## Monitoring & Debugging

### View Application Logs

```bash
# Tail logs
docker-compose logs -f

# Filter for errors
docker-compose logs | grep ERROR
```

### Check Queue Depth

```bash
aws --endpoint-url=http://localhost:4566 sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/direct-message-queue \
  --attribute-names ApproximateNumberOfMessages
```

### Check Circuit Breaker State

```bash
curl http://localhost:8080/actuator/metrics/resilience4j.circuitbreaker.state
```

### View Metrics

```bash
# All metrics
curl http://localhost:8080/actuator/metrics

# Specific metric
curl http://localhost:8080/actuator/metrics/resilience4j.circuitbreaker.calls
```

---

## Data Persistence

### Persistent Volumes

Docker Compose persists data in:
- **PostgreSQL**: `./postgres_data/`
- **LocalStack**: `./.localstack/`

### Reset Environment

To completely reset:

```bash
# Stop and remove volumes
docker-compose down -v

# Remove persistent data
rm -rf postgres_data .localstack

# Restart
docker-compose up -d

# Re-run bootstrap steps (Steps 2-3)
```

---

## Troubleshooting

### Application Won't Start

```bash
# Check if ports are in use
lsof -i :8080  # Application
lsof -i :5434  # PostgreSQL
lsof -i :4566  # LocalStack

# Check Docker logs
docker-compose logs postgres
docker-compose logs localstack
```

### Database Connection Failed

```bash
# Verify PostgreSQL is running
docker-compose ps postgres

# Test connection
psql -h localhost -p 5434 -U postgres -d event_db -c "SELECT 1;"
```

### LocalStack Not Responding

```bash
# Restart LocalStack
docker-compose restart localstack

# Check health
curl http://localhost:4566/_localstack/health

# View logs
docker-compose logs localstack
```

### Messages Not Processing

```bash
# Check queue exists
aws --endpoint-url=http://localhost:4566 sqs list-queues

# Check application logs
docker-compose logs | grep "DirectMessageListener"

# Verify circuit breaker is closed
curl http://localhost:8080/actuator/metrics/resilience4j.circuitbreaker.state
```

---

## Development Tips

### Hot Reload

For faster development, use Spring Boot DevTools:

```bash
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

Changes to Java files will trigger automatic restart.

### Database Migrations

Flyway runs automatically on startup. To add migrations:

1. Create file: `src/main/resources/db/migration/V3__description.sql`
2. Restart application
3. Verify: `psql -h localhost -p 5434 -U tmdev -d event_db -c "SELECT * FROM flyway_schema_history;"`

### Testing API Endpoints

Use the Swagger UI for interactive testing:

```bash
open http://localhost:8080/swagger-ui.html
```

---

## Useful Commands

### LocalStack

```bash
# List all queues
aws --endpoint-url=http://localhost:4566 sqs list-queues

# List S3 objects
aws --endpoint-url=http://localhost:4566 s3 ls s3://muralis-event-bucket-local --recursive

# Purge queue
aws --endpoint-url=http://localhost:4566 sqs purge-queue \
  --queue-url http://localhost:4566/000000000000/direct-message-queue
```

### Database

```bash
# Connect as admin
psql -h localhost -p 5434 -U postgres -d event_db

# Connect as app user
psql -h localhost -p 5434 -U tmdev -d event_db

# Dump schema
pg_dump -h localhost -p 5434 -U postgres -d event_db -n tmschema > schema.sql
```

### Docker

```bash
# View logs
docker-compose logs -f

# Restart service
docker-compose restart localstack

# Stop all
docker-compose down

# Remove volumes
docker-compose down -v
```

---

## Next Steps

Once local development is working:

1. Write unit tests (infrastructure ready with Testcontainers)
2. Add integration tests
3. Deploy to AWS (see [AWS Deployment Guide](aws_deploy.md))

---

For more details, see:
- [Architecture Overview](architecture.md)
- [FAQ](faq.md)
- [Main README](../README.md)
