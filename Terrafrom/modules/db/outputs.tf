output "db_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "db_instance_id" {
  value = aws_db_instance.mysql.id
}

output "db_sg_id" {
  value = aws_security_group.rds_sg.id
}
