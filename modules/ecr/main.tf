# Private registry for the app image. Tags are immutable, so a deployed tag
# (e.g. a git SHA) always means the same image and a rollback is just
# setting docker_tag back.
resource "aws_ecr_repository" "this" {
  name                 = "${var.project}-${var.environment}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ecr"
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent ${var.keep_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_images
      }
      action = { type = "expire" }
    }]
  })
}
