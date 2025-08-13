# Subnet group for RDS in private subnets
resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = { Name = "${var.project_name}-db-subnets" }
}

# Optional parameter group
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.project_name}-mysql-pg"
  family = "mysql8.0"
}

# MySQL instance (uses SG defined in security.tf: aws_security_group.rds_sg)
resource "aws_db_instance" "mysql" {
  identifier              = "${var.project_name}-mysql"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  username                = var.db_username
  password                = var.db_password
  db_name                 = var.db_name
  skip_final_snapshot     = true
  deletion_protection     = false
  multi_az                = false
  publicly_accessible     = false
  apply_immediately       = true
  parameter_group_name    = aws_db_parameter_group.mysql.name
  backup_retention_period = 0
  tags                    = { Name = "${var.project_name}-mysql" }
}
