# FAQ - Frequently Asked Questions

## Dead Letter Queue (DLQ) Management

### Q: What are the options I have with messages in the DLQ?

**Options for messages in the DLQ:**

**1. Inspect messages** (to understand the failure):
```bash
aws sqs receive-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/direct-message-queue-dlq.fifo \
  --max-number-of-messages 10 \
  --attribute-names All
```

**2. Delete individual messages** (after inspection):
```bash
aws sqs delete-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/direct-message-queue-dlq.fifo \
  --receipt-handle <receipt-handle-from-receive-message>
```

**3. Purge all messages** (clear the entire DLQ):
```bash
aws sqs purge-queue \
  --queue-url https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/direct-message-queue-dlq.fifo
```

**4. Redrive messages back to source queue** (after fixing the bug):
```bash
aws sqs start-message-move-task \
  --source-arn arn:aws:sqs:us-east-1:YOUR_ACCOUNT_ID:direct-message-queue-dlq.fifo \
  --destination-arn arn:aws:sqs:us-east-1:YOUR_ACCOUNT_ID:direct-message-queue.fifo
```

**5. Manually reprocess** by fixing the message format and sending corrected versions to the main queue.

**Most common workflow:** inspect → fix code/data → redrive OR purge if messages are invalid/not needed.

---

### Q: When do messages start being written into the DLQ?

Messages are written to the DLQ **after 3 failed processing attempts**.

Here's the flow:

1. **Attempt 1**: Message delivered → Spring app throws exception → message returns to queue
2. **Attempt 2**: Message redelivered → Spring app throws exception → message returns to queue  
3. **Attempt 3**: Message redelivered → Spring app throws exception → message returns to queue
4. **After 3rd failure**: SQS automatically moves the message to the DLQ

This is controlled by the `maxReceiveCount = 3` setting in [iac/modules/sqs/main.tf](../iac/modules/sqs/main.tf):

```hcl
redrive_policy = jsonencode({
  deadLetterTargetArn = aws_sqs_queue.direct_message_dlq.arn
  maxReceiveCount = 3
})
```

You can adjust `maxReceiveCount` to change how many retries happen before DLQ redrive (e.g., 5 attempts, 10 attempts, etc.).

---

### Q: If the application receives multiple invalid messages at different times (e.g., 3 messages at 7:11 AM, 7:12 AM, 7:13 AM, and a 4th message at 10:30 AM), will all of them be written to the DLQ?

**Yes**, all four messages will be written to the DLQ.

Each message is tracked **independently** by SQS. The DLQ behavior is based on **per-message retry count**, not cumulative failures across different messages.

Here's what happens:

**Messages 1-3 (7:11 AM, 7:12 AM, 7:13 AM):**
- Each message fails 3 times → each goes to DLQ

**Message 4 (10:30 AM):**
- Arrives and fails → Attempt 1
- Retried and fails → Attempt 2
- Retried and fails → Attempt 3
- After 3rd failure → **Goes to DLQ**

The time gap (3+ hours) doesn't matter. SQS tracks the `ApproximateReceiveCount` attribute for each individual message. Once any message reaches `maxReceiveCount = 3`, it's moved to the DLQ regardless of:
- How many other messages have failed
- When other messages arrived
- How much time has passed

**Key point**: The DLQ policy is per-message, not application-wide or time-based.

---

### Q: How does SQS track the same message each time it is retried?

SQS tracks messages using two key mechanisms:

**1. Message ID** - Each message gets a unique identifier when first sent to the queue. This ID remains the same across all retry attempts.

**2. ApproximateReceiveCount Attribute** - SQS maintains a counter that increments each time the message is received but **not deleted**.

**Here's how it works:**

1. **Message arrives** → SQS assigns a Message ID (e.g., `abc-123-xyz`)
2. **First processing attempt**:
   - App receives message → `ApproximateReceiveCount = 1`
   - Message becomes invisible (visibility timeout)
   - App throws exception → message is NOT deleted
   - After visibility timeout expires → message becomes visible again (same Message ID)

3. **Second attempt**:
   - Same message (same Message ID) received → `ApproximateReceiveCount = 2`
   - Fails again → not deleted → becomes visible after timeout

4. **Third attempt**:
   - Same message received → `ApproximateReceiveCount = 3`
   - Fails again → `ApproximateReceiveCount` reaches `maxReceiveCount`
   - **SQS automatically moves it to DLQ**

**Key point**: A message is only deleted from the queue when processing succeeds. Failed processing leaves the message in the queue with an incremented receive count. SQS uses the persistent Message ID and ApproximateReceiveCount to track retry attempts for that specific message.

---

### Q: Is the retry interval configurable?

**Yes**, the retry interval is configurable through the **visibility timeout** setting.

When a message fails processing (exception thrown, not deleted), it becomes invisible for the visibility timeout duration. After the timeout expires, the message becomes visible again for retry.

**Default**: SQS default visibility timeout is 30 seconds.

**To configure it**, add `visibility_timeout_seconds` to your queue configuration in [iac/modules/sqs/main.tf](../iac/modules/sqs/main.tf):

```hcl
resource "aws_sqs_queue" "direct_message_queue" {
  name = "${var.direct_message_queue_name}.fifo"
  fifo_queue = true
  content_based_deduplication = true
  visibility_timeout_seconds = 60  # 60 seconds before retry
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.direct_message_dlq.arn
    maxReceiveCount = 3
  })
}
```

**Common values:**
- `30` = 30 seconds (default)
- `60` = 1 minute
- `300` = 5 minutes
- `43200` = 12 hours (maximum)

**Choose based on**:
- How long your processing typically takes
- How quickly you want retries to happen
- Whether you want to avoid rapid retry storms

---

### Q: What is long polling?

**Long polling** is a technique where SQS waits for a period of time for messages to arrive in the queue before returning a response, rather than returning immediately with an empty result.

**Short polling (default):**
- Returns immediately, even if queue is empty
- May return empty responses frequently
- More API calls = higher costs

**Long polling:**
- Waits up to 20 seconds for messages to arrive
- Returns as soon as message(s) are available, or after the wait time expires
- Reduces empty responses
- Fewer API calls = lower costs
- More efficient

**To enable long polling**, configure `receive_wait_time_seconds` in your queue:

```hcl
resource "aws_sqs_queue" "direct_message_queue" {
  name = "${var.direct_message_queue_name}.fifo"
  fifo_queue = true
  content_based_deduplication = true
  receive_wait_time_seconds = 20  # Enable long polling (max 20 seconds)
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.direct_message_dlq.arn
    maxReceiveCount = 3
  })
}
```

**Recommendation**: Always use long polling (set to 20 seconds) to reduce costs and improve efficiency. Spring Cloud AWS SQS typically uses long polling by default.

---

### Q: How should I handle recoverable vs irrecoverable errors when invoking remote APIs after reading from SQS?

**Scenario**: After reading messages from SQS, you invoke remote APIs which can fail in two ways:
- **a) Recoverable Errors**: Network glitches, Service Unavailable (503)
- **b) Irrecoverable Errors**: Invalid Request (400), Authentication failure (401), Not Found (404)

**Implemented Strategy (Hybrid Approach)**:
- For category (a): Don't acknowledge message → SQS automatically retries (up to 3 times based on `maxReceiveCount`)
- For category (b): Acknowledge message and send directly to DLQ → No retry, immediate failure handling

**Key Design Decisions:**

**1. MANUAL Acknowledgment Mode**
- Using Spring Cloud AWS `Acknowledgment` parameter for fine-grained control
- Allows selective acknowledgment based on error type

**2. Single Failure Destination (DLQ Only)**
- Recoverable errors that persist beyond 3 retries → automatically go to **DLQ** (via SQS redrive policy)
- Irrecoverable errors → manually sent to **DLQ** immediately
- **Benefit**: Single place to monitor all failures

**3. Visibility Timeout Configuration**
- Set to 60 seconds to allow time for API calls and retries
- Configured in `iac/modules/sqs/main.tf`

**4. Exception Hierarchy**
- `RecoverableApiException`: 503, network errors, timeouts
- `IrrecoverableApiException`: 400, 401, 403, 404
- `DatabaseException`: Database-specific errors (treated as recoverable)

**Implemented Code:**

```java
@SqsListener(queueNames = "${sqs.direct-message-queue}")
public void receiveMessage(@Payload String messageBody, 
                          @Header("MessageId") String messageId,
                          Acknowledgment acknowledgment) {
    try {
        directMessageService.processMessage(messageBody, messageId);
        acknowledgment.acknowledge(); // Success - remove from queue
        
    } catch (IrrecoverableApiException e) {
        // 400, 401, 403, 404 - send directly to DLQ
        log.error("Irrecoverable error, sending to DLQ: {}", e.getMessage());
        sendToDlq(messageBody, messageId, e);
        acknowledgment.acknowledge(); // Remove from main queue
        
    } catch (RecoverableApiException | DatabaseException e) {
        // 503, network errors, DB errors - let SQS retry
        log.warn("Recoverable error, will retry: {}", e.getMessage());
        // Don't acknowledge - message returns to queue after visibility timeout
        
    } catch (Exception e) {
        // Unexpected errors - treat as recoverable
        log.error("Unexpected error, will retry: {}", e.getMessage(), e);
        // Don't acknowledge - message returns to queue
    }
}
```

**Benefits of This Approach:**
- ✅ Single failure destination (DLQ) - simpler monitoring
- ✅ No data loss risk - DLQ send failures are logged but message stays in main queue
- ✅ Automatic retry for transient failures via SQS
- ✅ Immediate failure handling for permanent errors
- ✅ Clear separation of error types
- ✅ Idempotency check prevents duplicate processing

**Monitoring:**
- CloudWatch alarm triggers when DLQ depth > 5 messages
- All failures (recoverable after 3 retries + irrecoverable) end up in same DLQ
- Single dashboard to monitor all failure types

---

### Q: Would it make sense to create an AI Agent that periodically reviews messages in the DLQ, provides analysis and recommendations, and writes them to S3 for human review via dashboard?

**Answer**: ✅ **Much better approach than autonomous fixes!** This adds value without the safety risks.

## Pros:

**1. Accelerated Diagnosis**
- AI can spot patterns humans might miss
- Contextual analysis of error types
- Grouped similar failures

**2. Human-in-the-Loop**
- Final decision stays with human
- Safe and auditable
- No data corruption risk

**3. Knowledge Capture**
- Analysis stored in S3 for historical review
- Team learning from AI insights
- Helps with documentation

**4. Prioritization**
- AI can rank by severity/impact
- Suggests which to fix first

## Cons:

**1. Privacy & Compliance**
- Sending production data to external AI service
- PII/PHI concerns - may need sanitization
- **Mitigation**: Redact sensitive fields before AI analysis

**2. Cost at Scale**
- AI API calls per failed message
- Can spike during incidents
- **Mitigation**: Batch analysis, rate limiting, budget alerts

**3. System Complexity**
- More moving parts to maintain
- Lambda/scheduled job, S3 integration, AI service
- **Mitigation**: Worth it if DLQ volume is significant

**4. AI Hallucination Risk**
- Recommendations might be wrong/misleading
- **Mitigation**: Clear disclaimers in dashboard, human validation

**5. Latency**
- Not real-time analysis
- Depends on trigger frequency
- **Mitigation**: Acceptable since human reviews anyway

## Architecture Recommendation:

```
DLQ → Lambda (scheduled) → AI Analysis → S3 Bucket → Dashboard
                ↓
        Sanitize PII first
```

**When This Makes Sense:**
- High DLQ volume (>50 messages/day)
- Complex error patterns
- Multiple team members need context
- Cost of manual analysis > AI cost

**When It Doesn't:**
- Low failure volume
- Simple, well-understood errors
- Small team that already knows patterns

**Recommendation**: ✅ **Solid approach** for medium-to-large scale operations. Start with a prototype on non-sensitive data to validate ROI.

---

## Database Setup and Schema Management

### Q: How is the database initialized and what schema is used?

The application uses a **two-phase database setup** with proper RBAC (Role-Based Access Control) and schema isolation:

**Phase 1: Infrastructure Setup (Terraform + Lambda Bootstrapper)**

When you run `terraform apply`, the infrastructure creates:
1. RDS PostgreSQL instance
2. Three database users with random passwords stored in AWS Secrets Manager:
   - `tmpower` - Migration user (DDL permissions)
   - `tmapp` - Application user (DML permissions only)
   - `tmdev` - Developer user (read-only)
3. Lambda function that executes `scripts/db_setup.sql` to configure RBAC

**What `db_setup.sql` does:**
```sql
-- Creates dedicated schema (NOT public)
CREATE SCHEMA IF NOT EXISTS tmschema;

-- Creates group roles (permission containers)
CREATE ROLE migration_grp NOLOGIN;    -- DDL permissions
CREATE ROLE application_grp NOLOGIN;  -- DML permissions
CREATE ROLE developer_grp NOLOGIN;    -- Read-only

-- Grants permissions to groups
GRANT ALL ON SCHEMA tmschema TO migration_grp;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tmschema TO application_grp;
GRANT SELECT ON ALL TABLES IN SCHEMA tmschema TO developer_grp;

-- Creates users and assigns to groups
CREATE USER tmpower WITH PASSWORD '<from-secrets-manager>';
CREATE USER tmapp WITH PASSWORD '<from-secrets-manager>';
CREATE USER tmdev WITH PASSWORD '<from-secrets-manager>';

GRANT migration_grp TO tmpower;
GRANT application_grp TO tmapp;
GRANT developer_grp TO tmdev;

-- Security hardening
REVOKE ALL ON SCHEMA public FROM PUBLIC;
```

**Phase 2: Application Startup (Flyway Migrations)**

When the Spring Boot application starts, Flyway runs as the `tmpower` user:

**Configuration in `application.yml`:**
```yaml
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?currentSchema=tmschema
    username: ${DB_USER:tmapp}
    password: ${DB_PASSWORD}
  
  flyway:
    enabled: true
    baseline-on-migrate: true
    default-schema: tmschema
    schemas: tmschema
    user: ${FLYWAY_USER:tmpower}
    password: ${FLYWAY_PASSWORD}
```

**Migration Scripts:**

**V1__init_schema.sql** (creates tables):
```sql
SET search_path TO tmschema;

CREATE TABLE IF NOT EXISTS direct_messages (
    id SERIAL PRIMARY KEY,
    city VARCHAR(255) NOT NULL,
    country VARCHAR(255) NOT NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_file_uploads (
    id SERIAL PRIMARY KEY,
    bucket_name VARCHAR(255) NOT NULL,
    object_key VARCHAR(512) NOT NULL,
    content TEXT,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**V2__add_message_id.sql** (adds idempotency column):
```sql
SET search_path TO tmschema;

ALTER TABLE direct_messages ADD COLUMN message_id VARCHAR(255) UNIQUE;
CREATE INDEX idx_direct_messages_message_id ON direct_messages(message_id);
```

---

### Q: Why use a dedicated schema instead of the public schema?

Using a dedicated schema (`tmschema`) instead of `public` is a **production best practice** for several reasons:

**1. Security Isolation**
- `public` schema is accessible to all users by default
- Custom schema allows fine-grained access control
- Prevents accidental access from other applications sharing the database

**2. Multi-Tenancy Support**
- Multiple applications can use the same database instance
- Each application gets its own schema
- No naming conflicts or cross-contamination

**3. Clear Ownership**
- Schema name indicates which application owns the tables
- Easier to identify and manage resources
- Better for auditing and compliance

**4. Migration Safety**
- Flyway metadata (`flyway_schema_history`) stays in `tmschema`
- No interference with other applications' migrations
- Cleaner rollback and version management

**5. Principle of Least Privilege**
- Application user (`tmapp`) only has access to `tmschema`
- Cannot accidentally modify other schemas
- Reduces blast radius of security incidents

---

### Q: What are the different database users and their permissions?

The application uses **three separate users** with different permission levels:

| User | Role | Permissions | Used By | Password Storage |
|------|------|-------------|---------|------------------|
| `tmpower` | Migration | DDL (CREATE, ALTER, DROP) on `tmschema` | Flyway migrations | AWS Secrets Manager |
| `tmapp` | Application | DML (SELECT, INSERT, UPDATE, DELETE) on `tmschema` | Spring Boot runtime | AWS Secrets Manager |
| `tmdev` | Developer | SELECT only on `tmschema` | Manual queries, debugging | AWS Secrets Manager |

**Why separate users?**

**1. Principle of Least Privilege**
- Application cannot accidentally drop tables or modify schema
- Reduces risk of SQL injection attacks causing schema damage
- Developer access is read-only to prevent accidental data modification

**2. Audit Trail**
- Database logs show which user performed which action
- Easy to track schema changes vs data changes
- Better compliance and security monitoring

**3. Credential Rotation**
- Can rotate application credentials without affecting migrations
- Can revoke developer access without impacting production
- Independent lifecycle management

**4. Defense in Depth**
- Even if application is compromised, attacker cannot modify schema
- Limits damage from SQL injection or code vulnerabilities
- Multiple layers of security

---

### Q: How do I retrieve database passwords from AWS Secrets Manager?

After running `terraform apply`, retrieve passwords using these commands:

**Master Password (tmpower):**
```bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=iac output -raw tmpower_password_secret_arn) \
  --query SecretString --output text
```

**Application Password (tmapp):**
```bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=iac output -raw tmapp_password_secret_arn) \
  --query SecretString --output text
```

**Developer Password (tmdev):**
```bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=iac output -raw tmdev_password_secret_arn) \
  --query SecretString --output text
```

**Note**: The Spring Boot application automatically retrieves these passwords from Secrets Manager at startup using the AWS SDK. You only need to retrieve them manually for direct database access or debugging.

---

### Q: What happens on a fresh deployment from scratch?

**Complete deployment flow:**

1. **Terraform creates infrastructure** (`terraform apply`):
   - RDS PostgreSQL instance
   - Three random passwords stored in Secrets Manager
   - Lambda function with `db_setup.sql` embedded
   - VPC, security groups, SQS queues, S3 bucket, etc.

2. **Lambda bootstrapper executes** (triggered by Terraform):
   - Connects to RDS as master user
   - Runs `db_setup.sql`
   - Creates `tmschema` schema
   - Creates roles: `migration_grp`, `application_grp`, `developer_grp`
   - Creates users: `tmpower`, `tmapp`, `tmdev` with Secrets Manager passwords
   - Grants permissions
   - Hardens security (revokes public schema access)

3. **Docker image built and pushed** (`scripts/cicd.sh`):
   - Maven builds JAR
   - Docker builds image
   - Image pushed to ECR

4. **ECS service starts** (Terraform creates ECS task):
   - Container starts with environment variables pointing to Secrets Manager
   - Spring Boot retrieves database passwords from Secrets Manager
   - Flyway connects as `tmpower` user
   - Flyway runs migrations in `tmschema`:
     - V1: Creates `direct_messages` and `s3_file_uploads` tables
     - V2: Adds `message_id` column with unique constraint
   - Application switches to `tmapp` user for runtime operations
   - Application starts processing messages

**Result**: Fully configured database with proper RBAC, schema isolation, and all tables created in `tmschema`.

---

## CI/CD and Infrastructure Pipeline

### Q: How do we bridge Terraform outputs to GitHub Actions?

In a decoupled world where **HCP Terraform** manages infrastructure and **GitHub Actions (GHA)** manages code, there are several patterns for bridging outputs (like `ecr_repository_url`):

**1. Direct Capture**
- Running `terraform apply` within a GHA step and mapping raw outputs to GHA environment variables

**2. Remote State Discovery**
- Using a `terraform_remote_state` data source in a small GHA-specific Terraform config to "look up" outputs from the main workspace

**3. HCP Terraform API**
- Using the `hashicorp/setup-terraform` action to pull workspace outputs via the Cloud API

**4. AWS "Source of Truth" Pattern (Enterprise Strategy)**
- **Concept**: Infrastructure (Terraform) writes key metadata into **AWS SSM Parameter Store** (e.g., `/prod/messaging/ecr-url`)
- **Benefit**: The CI/CD pipeline (GHA) simply queries a stable AWS path instead of depending on brittle Terraform outputs. This completely decouples the application release from the infrastructure code
- **Future Roadmap**: We will pivot to this pattern once the initial cloud footprint is stable

---

### Q: Can we use AWS CodePipeline instead of GitHub Actions?

**Yes**, this is the **Gold Standard** for AWS-native DevSecOps.

**Benefits:**

**1. Terraform Provisions the Pipeline**
- Terraform creates the `aws_codepipeline`, `aws_codebuild`, and required IAM roles

**2. Zero-Credential CI/CD**
- Since CodeBuild runs natively within your AWS VPC, it uses IAM Roles for ECR/ECS access
- Eliminates the need to store long-lived AWS Access Keys in external CI providers

**3. Bake-in Health Checks**
- CodePipeline natively manages the transition and health verification that we currently handle via script-based "waiting"

**4. Built-in Compliance**
- Native AWS audit trails and compliance logs

**Future Roadmap**: We plan to adopt this AWS-native approach to leverage built-in compliance logs and audit trails.

---

## Idempotency and Duplicate Message Handling

### Q: Why do we need the idempotency check? What are the concerns if it is eliminated?

**Short Answer**: The idempotency check prevents duplicate processing when messages are redelivered due to app crashes, network issues, or deduplication window expiration. Without it, you'd get duplicate database records, wasted API calls, and retry loops from constraint violations.

---

### When Do Duplicate Messages Occur in FIFO Queues?

Even with FIFO queues and content-based deduplication, duplicates can still occur in these scenarios:

#### Scenario 1: App Crashes After DB Save, Before Acknowledgment ✅
```
1. Message received and locked to Consumer A
2. Processing completes, DB save successful
3. App crashes before acknowledgment sent
4. After visibility timeout, message becomes visible again
5. Same or different consumer picks it up → DUPLICATE
```

**Why it happens**: The acknowledgment never reaches SQS, so SQS assumes the message wasn't processed.

---

#### Scenario 2: Network Issue During Acknowledgment ✅
```
1. Message processed successfully
2. DB save successful  
3. Acknowledgment sent but network fails
4. SQS never receives acknowledgment
5. After visibility timeout, message reprocessed → DUPLICATE
```

**Why it happens**: Network partition or timeout prevents SQS from receiving the acknowledgment.

---

#### Scenario 3: Deduplication Window Expires ⚠️
```
1. Message sent with messageId="abc123"
2. Processed successfully
3. 6 minutes later, another message sent with same messageId
4. Deduplication window (5 min) expired
5. SQS treats it as new message → DUPLICATE
```

**Why it happens**: SQS content-based deduplication only works for 5 minutes. After that, the same logical message is treated as new.

---

#### Scenario 4: Producer Bugs
```
1. Message producer accidentally sends duplicates with different deduplication IDs
2. SQS can't deduplicate them (different IDs)
3. Both messages processed → DUPLICATE
```

**Why it happens**: Application bug in the message producer.

---

### What Happens Without Idempotency Check?

**With UNIQUE Constraint But No Idempotency Check:**

When a duplicate message arrives:
1. ✅ Weather API called (unnecessary work, wasted resources)
2. ✅ Weather logged (unnecessary work)
3. ❌ Database save fails with `UNIQUE CONSTRAINT VIOLATION`
4. Exception thrown → message not acknowledged
5. SQS retries → infinite loop of failures
6. After 3 retries → message goes to DLQ

**Result**: Message stuck in retry loop and eventually sent to DLQ, even though it was already processed successfully by another instance.

---

**With UNIQUE Constraint AND Idempotency Check:**

When a duplicate message arrives:
1. ✅ Idempotency check: "Already processed, skipping"
2. ✅ Message acknowledged immediately
3. ✅ No wasted weather API calls
4. ✅ No exception, no retry loop
5. ✅ Clean logs, no constraint violations

**Result**: Duplicate handled gracefully, no wasted resources, no DLQ pollution.

---

### Why Keep the Idempotency Check?

**1. Performance**
- Avoids unnecessary weather API calls on duplicates
- Saves network bandwidth and processing time

**2. Clean Logs**
- No constraint violation exceptions cluttering logs
- Duplicates logged as informational, not errors

**3. Proper Acknowledgment**
- Duplicates are acknowledged cleanly
- No retry loops or DLQ pollution

**4. Cost Optimization**
- Avoids unnecessary external API calls
- Even free APIs have rate limits

**5. Graceful Handling**
- Treats duplicates as expected behavior, not errors
- Better observability and monitoring

**6. Defense-in-Depth**
- Database constraint is last line of defense
- Idempotency check is first line of defense
- Multiple layers of protection

---

### Cost of Idempotency Check

**Very low**: One SELECT query per message
```sql
SELECT COUNT(*) FROM direct_messages WHERE message_id = ?
```

This is negligible compared to:
- Weather API calls (2 HTTP requests)
- Database INSERT operation
- Message processing logic

---

### Alternative: Remove Idempotency Check?

You *could* remove it if you're okay with:
- ❌ Wasting weather API calls on duplicates
- ❌ Seeing constraint violation exceptions in logs
- ❌ Messages going to DLQ when they're actually duplicates of successful processing
- ❌ Higher costs and resource usage
- ❌ Messier logs and monitoring

**Recommendation**: Keep the idempotency check. It's a best practice for distributed systems, costs very little (one SELECT query), and provides significant benefits in reliability, performance, and operational clarity.

---

### FIFO Queue Clarification

**Important Note**: In FIFO queues with message group IDs, all messages with the same `MessageGroupId` are processed **in order** by the **same consumer**. This means you won't have two consumers processing the same message simultaneously.

However, this doesn't eliminate the need for idempotency because:
- App crashes can happen after processing but before acknowledgment
- Network issues can prevent acknowledgment from reaching SQS
- Deduplication window (5 minutes) can expire
- Producer bugs can send duplicates with different deduplication IDs

The idempotency check protects against all these scenarios.
---

## AWS Networking and Connectivity

### Q: How is the application running within ECS in my VPC able to access external applications on the internet via HTTP API calls?

Your ECS application can access external internet APIs (like `https://api.open-meteo.com`) through this network setup:

#### 1. Public Subnets with Internet Gateway

Your ECS tasks run in **public subnets** that have:
- `map_public_ip_on_launch = true` - automatically assigns public IP addresses
- An **Internet Gateway** attached to the VPC
- A **route table** with a default route (`0.0.0.0/0`) pointing to the Internet Gateway

From [iac/modules/vpc/main.tf](../iac/modules/vpc/main.tf):
```hcl
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "event-driven-gw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}
```

#### 2. ECS Service Configuration

From [iac/modules/ecs/main.tf](../iac/modules/ecs/main.tf):
```hcl
network_configuration {
  subnets          = var.subnet_ids          # Public subnets
  security_groups  = [aws_security_group.ecs.id]
  assign_public_ip = true                    # Key setting!
}
```

The `assign_public_ip = true` gives each ECS task a **public IP address**.

#### 3. Security Group Egress Rules

From [iac/modules/ecs/main.tf](../iac/modules/ecs/main.tf):
```hcl
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]  # Allows all outbound traffic
}
```

This allows your container to make HTTP/HTTPS calls to anywhere on the internet.

#### 4. Traffic Flow

```
ECS Task (with public IP) 
    → Security Group (allows egress to 0.0.0.0/0)
    → Internet Gateway
    → Internet (e.g., https://api.open-meteo.com)
```

Your application can call external APIs like:
- `https://geocoding-api.open-meteo.com/v1/search` (geocoding)
- `https://api.open-meteo.com/v1/forecast` (weather data)

#### Alternative: Private Subnets with NAT Gateway (Production Recommendation)

For enhanced security in production, consider this architecture:

```
ECS Task (private subnet, no public IP)
    → NAT Gateway (in public subnet)
    → Internet Gateway
    → Internet
```

**Benefits:**
- ✅ Better security - tasks not directly accessible from internet
- ✅ Static egress IP for API whitelisting
- ✅ Follows AWS best practices

**Tradeoffs:**
- ⚠️ Additional cost for NAT Gateway (~$0.045/hour + data transfer)
- ⚠️ Single point of failure (mitigate with NAT Gateway per AZ)

**Current Setup:** Your architecture uses public subnets with public IPs, which works and is simpler/cheaper, but exposes tasks with public IPs (though ingress is still controlled by security groups).

To implement private subnets with NAT Gateway, you would:
1. Create private subnets
2. Create NAT Gateway in public subnet
3. Route private subnet traffic through NAT Gateway
4. Set `assign_public_ip = false` in ECS service
5. Update security group to only allow traffic from within VPC on ingress

---