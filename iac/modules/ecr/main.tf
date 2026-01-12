resource "aws_ecr_repository" "app" {
  name                 = "event-driven-microservice"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

output "repository_url" {
  value = aws_ecr_repository.app.repository_url
}
