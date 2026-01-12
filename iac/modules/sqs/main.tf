resource "aws_sqs_queue" "s3_event_queue" {
  name = var.s3_event_queue_name
}

resource "aws_sqs_queue" "direct_message_dlq" {
  name = "${var.direct_message_queue_name}-dlq.fifo"
  fifo_queue = true
  content_based_deduplication = true
}

resource "aws_sqs_queue" "direct_message_queue" {
  name = "${var.direct_message_queue_name}.fifo"
  fifo_queue = true
  content_based_deduplication = true
  visibility_timeout_seconds = 60
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.direct_message_dlq.arn
    maxReceiveCount = 3
  })
}

variable "s3_event_queue_name" {
  type = string
}

variable "direct_message_queue_name" {
  type = string
}

output "s3_event_queue_arn" {
  value = aws_sqs_queue.s3_event_queue.arn
}

output "s3_event_queue_url" {
  value = aws_sqs_queue.s3_event_queue.id
}

output "direct_message_queue_url" {
  value = aws_sqs_queue.direct_message_queue.id
}

output "s3_event_queue_id" {
  value = aws_sqs_queue.s3_event_queue.id
}

output "direct_message_dlq_url" {
  value = aws_sqs_queue.direct_message_dlq.id
}

output "direct_message_dlq_arn" {
  value = aws_sqs_queue.direct_message_dlq.arn
}
