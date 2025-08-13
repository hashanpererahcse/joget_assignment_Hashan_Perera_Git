variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "joget-assignment"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (2)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (2)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "allowed_ssh_cidr" {
  description = "public IP in CIDR to reach bastion"
  type        = string
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name"
  type        = string
}

variable "db_name" {
  description = "Joget DB name"
  type        = string
  default     = "jwdb"
}

variable "db_username" {
  description = "DB master username"
  type        = string
  default     = "jogetadmin"
}

variable "db_password" {
  description = "DB master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage (GiB)"
  type        = number
  default     = 20
}