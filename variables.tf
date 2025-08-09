variable "project" {
  description = "Project/name prefix"
  type        = string
  default     = "hybrid-poc"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Two /24 CIDRs for public subnets"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Two /24 CIDRs for private subnets"
  type        = list(string)
  default     = ["10.20.20.0/24", "10.20.21.0/24"]
}

variable "instance_type_app" {
  description = "EC2 instance type for app nodes"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_web" {
  description = "EC2 instance type for standalone Apache web server"
  type        = string
  default     = "t3.micro"
}

variable "create_web_server" {
  description = "Whether to create the separate Apache web server EC2"
  type        = bool
  default     = true
}

variable "key_name" {
  description = "Optional EC2 key pair to attach"
  type        = string
  default     = null
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "appadmin"
}

variable "db_name" {
  description = "Initial DB name"
  type        = string
  default     = "appdb"
}

variable "allowed_admin_cidr" {
  description = "Your IP/CIDR for optional SSH (commented out by default)"
  type        = string
  default     = "0.0.0.0/32"
}
