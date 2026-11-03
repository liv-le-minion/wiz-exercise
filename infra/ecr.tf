resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-tasky"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  # Scan images for known vulnerabilities on every push
  image_scanning_configuration {
    scan_on_push = true
  }
}
