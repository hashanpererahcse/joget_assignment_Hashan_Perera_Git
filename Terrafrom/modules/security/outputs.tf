output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}

output "ec2_sg_id" {
  value = aws_security_group.ec2_sg.id
}

output "iam_instance_profile" {
  value = aws_iam_instance_profile.ec2_profile.name
}
