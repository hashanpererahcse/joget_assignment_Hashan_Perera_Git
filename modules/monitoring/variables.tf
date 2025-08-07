variable "ec2_instance_ids" {
  type = list(string)
}

variable "db_instance_id" {}

variable "alb_arn" {}

variable "alb_arn_suffix" {}
variable "target_group_arn_suffix" {}
