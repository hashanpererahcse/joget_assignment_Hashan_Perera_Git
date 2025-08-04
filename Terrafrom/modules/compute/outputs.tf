output "instance_ids" {
  value = aws_instance.app[*].id
}

output "alb_dns" {
  value = aws_lb.app_alb.dns_name
}

output "alb_arn" {
  value = aws_lb.app_alb.arn
}
