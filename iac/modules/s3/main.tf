resource "aws_s3_bucket" "event_bucket" {
  bucket = var.bucket_name
}

variable "bucket_name" {
  type = string
}

output "bucket_arn" {
  value = aws_s3_bucket.event_bucket.arn
}

output "bucket_name" {
  value = aws_s3_bucket.event_bucket.id
}

output "bucket_id" {
  value = aws_s3_bucket.event_bucket.id
}
