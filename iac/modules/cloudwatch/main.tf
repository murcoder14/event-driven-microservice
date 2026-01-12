# CloudWatch Alarms for SQS DLQ
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "direct-message-dlq-high-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "Alert when DLQ has more than 5 messages"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    QueueName = var.dlq_name
  }
}

# CloudWatch Alarm for SQS Main Queue Age
resource "aws_cloudwatch_metric_alarm" "queue_message_age" {
  alarm_name          = "direct-message-queue-old-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "300"
  alarm_description   = "Alert when messages are older than 5 minutes"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    QueueName = var.queue_name
  }
}

# CloudWatch Alarm for ECS Service CPU
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "ecs-service-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when ECS CPU is above 80%"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }
}

# CloudWatch Alarm for ECS Service Memory
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "ecs-service-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when ECS Memory is above 80%"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }
}

# CloudWatch Log Group for Custom Metrics
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "ErrorCount"
  log_group_name = var.log_group_name
  pattern        = "[time, request_id, level = ERROR*, ...]"
  
  metric_transformation {
    name      = "ErrorCount"
    namespace = "EventDrivenMicroservice"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "application_errors" {
  alarm_name          = "application-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ErrorCount"
  namespace           = "EventDrivenMicroservice"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when application has more than 10 errors in 5 minutes"
  treat_missing_data  = "notBreaching"
}

variable "dlq_name" {
  type = string
}

variable "queue_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "log_group_name" {
  type = string
}

output "dlq_alarm_arn" {
  value = aws_cloudwatch_metric_alarm.dlq_messages.arn
}

output "queue_age_alarm_arn" {
  value = aws_cloudwatch_metric_alarm.queue_message_age.arn
}
