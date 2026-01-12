# Event-Driven Microservice

A production-ready Spring Boot microservice demonstrating event-driven architecture with AWS services (SQS, S3, RDS, ECS) and comprehensive operational maturity.

[![Java](https://img.shields.io/badge/Java-25-orange.svg)](https://openjdk.org/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-4.0.1-brightgreen.svg)](https://spring.io/projects/spring-boot)
[![AWS](https://img.shields.io/badge/AWS-Cloud-orange.svg)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-purple.svg)](https://www.terraform.io/)

---

## 🎯 Overview

This microservice processes events from multiple sources:
- **SQS Messages** - Direct messages with city/country data, fetches weather information
- **S3 Events** - File upload notifications, downloads and processes files

All events are persisted to PostgreSQL with full idempotency, error handling, and monitoring.

### Key Features

✅ **Production Ready**
- Comprehensive error handling with circuit breaker and retry
- Full monitoring with CloudWatch alarms and metrics
- Security scanning (OWASP, Trivy)
- Graceful shutdown and health checks
- Structured JSON logging
- API documentation with Swagger

✅ **Resilient Architecture**
- Circuit breaker pattern (Resilience4j)
- Retry with exponential backoff
- Hybrid error handling (DLQ for irrecoverable, retry for recoverable)
- Idempotency checks
- Transaction management

✅ **Operational Maturity**
- CloudWatch alarms (DLQ, CPU, memory, errors)
- Health endpoints (liveness, readiness)
- Metrics export to CloudWatch
- Code quality enforcement (Checkstyle, SpotBugs, JaCoCo)
- Container vulnerability scanning

---

## 🚀 Quick Start

### Prerequisites

- **Java 25** (JDK 25 or later)
- **Maven 3.9+**
- **Docker** (for LocalStack and PostgreSQL)
- **AWS CLI** (configured with credentials)
- **Terraform 1.5+**

### Local Development

```bash
# 1. Start LocalStack and PostgreSQL
docker-compose up -d

# 2. Run the application
./local_run.sh

# 3. Send test messages
./scripts/verify_deployment.sh
```

The application will be available at `http://localhost:8080`

### AWS Deployment

```bash
# 1. Create infrastructure
./scripts/iac_create.sh

# 2. Deploy application
./scripts/cicd.sh

# 3. Verify deployment
./scripts/verify_deployment.sh
```

---

## 📚 Documentation

### Getting Started
- [Local Development Guide](docs/local_run.md) - Complete local setup with all commands
- [AWS Deployment Guide](docs/aws_deploy.md) - Complete AWS deployment with all commands

### Architecture & Design
- [Architecture Overview](docs/architecture.md) - System design and components
- [FAQ](docs/faq.md) - Frequently asked questions (includes idempotency)

### Implementation Details
- [Implementation Details](docs/implementation_details.md) - Production readiness features

### API Documentation
- Swagger UI: `http://localhost:8080/swagger-ui.html` (when running)
- OpenAPI Spec: `http://localhost:8080/v3/api-docs`

---

## 🏗️ Architecture

```
┌─────────────┐     ┌─────────────┐
│   S3 Bucket │────▶│ SQS Queue   │
└─────────────┘     │ (S3 Events) │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐     ┌─────────────┐
                    │     ECS     │────▶│     RDS     │
                    │  (Spring    │     │ (PostgreSQL)│
                    │   Boot)     │     └─────────────┘
                    └──────┬──────┘
                           │
                           ▲
                    ┌──────┴──────┐
                    │ SQS Queue   │
                    │ (Direct Msg)│
                    └─────────────┘
                           │
                    ┌──────┴──────┐
                    │     DLQ     │
                    │  (Failed)   │
                    └─────────────┘
```

### Components

- **ECS Fargate** - Serverless container hosting
- **RDS PostgreSQL** - Relational database
- **SQS FIFO Queues** - Message queuing with ordering
- **S3** - Object storage
- **CloudWatch** - Monitoring and alarms
- **Secrets Manager** - Credential management
- **VPC** - Network isolation

---

## 🔧 Technology Stack

### Application
- **Spring Boot 4.0.1** - Application framework
- **Spring Cloud AWS 4.0.0-M1** - AWS integration
- **Resilience4j** - Circuit breaker and retry
- **Flyway** - Database migrations
- **HikariCP** - Connection pooling
- **RestClient** - HTTP client (Spring Framework 6+)

### Infrastructure
- **Terraform** - Infrastructure as Code
- **Docker** - Containerization
- **Google Jib** - Container image building
- **LocalStack** - Local AWS emulation

### Monitoring & Quality
- **Spring Boot Actuator** - Health and metrics
- **Micrometer** - Metrics collection
- **Logstash Encoder** - Structured logging
- **Checkstyle** - Code style
- **SpotBugs** - Static analysis
- **JaCoCo** - Code coverage
- **OWASP Dependency Check** - Security scanning
- **Trivy** - Container scanning

---

## 📊 Monitoring

### Health Endpoints

```bash
# Overall health
curl http://localhost:8080/actuator/health

# Liveness probe (Kubernetes-style)
curl http://localhost:8080/actuator/health/liveness

# Readiness probe (Kubernetes-style)
curl http://localhost:8080/actuator/health/readiness
```

### Metrics

```bash
# All metrics
curl http://localhost:8080/actuator/metrics

# Circuit breaker state
curl http://localhost:8080/actuator/metrics/resilience4j.circuitbreaker.state

# Prometheus format
curl http://localhost:8080/actuator/prometheus
```

### CloudWatch Alarms

- **DLQ High Depth** - Alerts when > 5 messages
- **Queue Message Age** - Alerts when > 5 minutes old
- **ECS High CPU** - Alerts when > 80%
- **ECS High Memory** - Alerts when > 80%
- **Application Errors** - Alerts when > 10 errors in 5 minutes

---

## 🧪 Testing

### Code Quality

```bash
# Run all quality checks
mvn checkstyle:check spotbugs:check test

# Generate coverage report
mvn jacoco:report
# View: target/site/jacoco/index.html
```

### Security Scanning

```bash
# Dependency vulnerabilities
mvn dependency-check:check

# Container vulnerabilities (requires Trivy)
trivy image <ECR_REPO_URL>:latest
```

### Integration Tests

```bash
# Run tests (when implemented)
mvn verify

# With Testcontainers
mvn verify -Dspring.profiles.active=test
```

---

## 🔐 Security

### Implemented Controls

- ✅ Secrets stored in AWS Secrets Manager
- ✅ Rotation configuration (30-day cycle)
- ✅ IAM least privilege policies
- ✅ VPC isolation for RDS
- ✅ Security group network isolation
- ✅ Dependency vulnerability scanning
- ✅ Container vulnerability scanning
- ✅ CVSS threshold enforcement (≥ 7 fails build)

### Scanning

```bash
# Check for vulnerable dependencies
mvn dependency-check:check

# Scan container image
trivy image --severity HIGH,CRITICAL <IMAGE>
```

---

## 🔄 CI/CD Pipeline

### Pipeline Stages

1. **Validation** - Environment and tool checks
2. **Build** - Maven compile and Jib build
3. **Security Scan** - Trivy vulnerability scanning
4. **Deploy** - Terraform apply with new image
5. **Monitor** - Wait for deployment stability
6. **Verify** - Health check validation

### Deployment

```bash
# Full deployment
./scripts/cicd.sh

# Monitor deployment
aws ecs describe-services \
  --cluster event-driven-cluster \
  --services event-driven-service
```

---

## 🛠️ Configuration

### Environment Variables

```bash
# Database
DB_HOST=<rds-endpoint>
DB_PORT=5432
DB_NAME=event_db
DB_USER=tmapp
DB_PASSWORD=<from-secrets-manager>
DB_SCHEMA=tmschema

# AWS
AWS_REGION=us-east-1
S3_EVENT_QUEUE=s3-event-queue
DIRECT_MESSAGE_QUEUE=direct-message-queue
DIRECT_MESSAGE_DLQ=direct-message-queue-dlq

# Monitoring
CLOUDWATCH_METRICS_ENABLED=true
SPRING_PROFILES_ACTIVE=aws
```

### Application Profiles

- `local` - Local development with LocalStack
- `aws` - AWS deployment with CloudWatch
- `test` - Testing with Testcontainers

---

## 📈 Performance

### Concurrency Settings

```yaml
# SQS listener configuration
spring.cloud.aws.sqs.listener:
  max-concurrent-messages: 10  # Max concurrent message processing
  max-messages-per-poll: 5     # Messages per poll
```

### Circuit Breaker

```yaml
# Weather API circuit breaker
resilience4j.circuitbreaker.instances.weatherApi:
  failureRateThreshold: 50      # Open at 50% failure rate
  waitDurationInOpenState: 30s  # Wait 30s before half-open
  slidingWindowSize: 10         # Track last 10 calls
```

### Retry Configuration

```yaml
# Weather API retry
resilience4j.retry.instances.weatherApi:
  maxAttempts: 3                      # Max 3 attempts
  waitDuration: 1s                    # Initial wait
  exponentialBackoffMultiplier: 2     # 1s, 2s, 4s
```

---

## 🐛 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Application won't start | Check ECS task logs, verify database connectivity |
| Messages not processing | Check queue depth, DLQ, circuit breaker state |
| High error rate | Check CloudWatch alarms, review logs |
| Database connection errors | Verify RDS status, security groups |

### Debug Commands

```bash
# Check ECS task status
aws ecs describe-tasks --cluster event-driven-cluster --tasks <TASK_ARN>

# View logs
aws logs tail /ecs/event-driven-microservice --follow

# Check queue depth
aws sqs get-queue-attributes --queue-url <QUEUE_URL> \
  --attribute-names ApproximateNumberOfMessages

# Check circuit breaker state
curl http://localhost:8080/actuator/metrics/resilience4j.circuitbreaker.state
```

See [Quick Reference](#-quick-reference) section above for common commands.

---

## 📝 Project Structure

```
.
├── docs/                          # Documentation
│   ├── architecture.md           # Architecture overview
│   ├── aws_deploy.md            # AWS deployment guide
│   ├── local_run.md             # Local development guide
│   ├── faq.md                   # FAQ and idempotency
│   └── implementation_details.md # Implementation details
├── iac/                          # Terraform infrastructure
│   ├── modules/                 # Terraform modules
│   │   ├── cloudwatch/         # CloudWatch alarms
│   │   ├── ecs/                # ECS service
│   │   ├── rds/                # RDS database
│   │   ├── s3/                 # S3 bucket
│   │   ├── sqs/                # SQS queues
│   │   └── vpc/                # VPC networking
│   ├── backend.tf              # S3 backend config
│   └── main.tf                 # Main configuration
├── scripts/                      # Deployment scripts
│   ├── cicd.sh                 # CI/CD pipeline
│   ├── iac_create.sh           # Infrastructure creation
│   └── verify_deployment.sh    # Deployment verification
├── src/                          # Application source
│   ├── main/
│   │   ├── java/               # Java source code
│   │   └── resources/          # Configuration files
│   └── test/                   # Test source code
├── docker-compose.yml           # Local development
├── pom.xml                      # Maven configuration
└── README.md                    # This file
```

---

## 🤝 Contributing

### Code Quality Standards

- Follow Google Java Style Guide (enforced by Checkstyle)
- Maintain >50% code coverage (enforced by JaCoCo)
- Fix all SpotBugs warnings
- No HIGH or CRITICAL vulnerabilities (OWASP, Trivy)

### Development Workflow

1. Create feature branch
2. Make changes
3. Run quality checks: `mvn checkstyle:check spotbugs:check test`
4. Run security scan: `mvn dependency-check:check`
5. Submit pull request

---

## 📄 License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## 🙏 Acknowledgments

- Spring Boot team for excellent framework
- AWS for cloud services
- Resilience4j for resilience patterns
- Open-Meteo for weather API

---

## 📞 Support

For questions or issues:
1. Check [FAQ](docs/faq.md)
2. Review [Local Development Guide](docs/local_run.md) or [AWS Deployment Guide](docs/aws_deploy.md)
3. Check CloudWatch logs and alarms
4. Review troubleshooting sections in deployment guides

---

**Status:** ✅ Production Ready  
**Last Updated:** January 11, 2026  
**Next Review:** February 11, 2026
