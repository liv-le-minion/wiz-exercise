output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "mongo_public_ip" {
  value = aws_instance.mongo.public_ip
}

output "mongo_private_ip" {
  value = aws_instance.mongo.private_ip
}

output "mongo_admin_password" {
  value     = random_password.mongo_admin.result
  sensitive = true
}

output "mongo_app_password" {
  value     = random_password.mongo_app.result
  sensitive = true
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "backup_bucket_url" {
  value = "https://${aws_s3_bucket.backups.bucket}.s3.${var.region}.amazonaws.com/"
}
