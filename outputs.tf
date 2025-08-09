output "alb_dns_name" {
  value       = aws_lb.app_alb.dns_name
  description = "ALB DNS — your app entrypoint"
}

output "rds_endpoint" {
  value       = aws_db_instance.mysql.address
  description = "RDS endpoint"
}

output "db_secret_name" {
  value       = aws_secretsmanager_secret.db.name
  description = "Secrets Manager secret name for DB credentials"
}
