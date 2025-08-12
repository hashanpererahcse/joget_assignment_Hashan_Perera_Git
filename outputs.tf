output "alb_dns_name" {
  description = "Public ALB DNS name"
  value       = aws_lb.alb.dns_name
}

output "bastion_public_ip" {
  description = "Bastion public IP"
  value       = aws_instance.bastion.public_ip
}

output "vpc_id" { value = aws_vpc.this.id }