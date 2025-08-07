variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "joget-app"
}

variable "key_name" {
  description = "EC2 key pair name"
  default     = "jogetapp-keypair"
}

variable "db_username" {
  default = "admin"
}

variable "db_password" {
  default = "password123"
}

variable "alb_arn_suffix" {
  default = "app/joget-app-alb/abc123"
}

variable "target_group_arn_suffix" {
  default = "targetgroup/joget-app-tg/xyz789"
}
