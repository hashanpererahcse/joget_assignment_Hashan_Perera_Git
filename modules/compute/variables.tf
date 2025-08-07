variable "vpc_id" {}
variable "public_subnet_ids" {
  type = list(string)
}
variable "alb_sg_id" {}
variable "ec2_sg_id" {}
variable "key_name" {}
variable "project_name" {
  default = "joget-app"
}
