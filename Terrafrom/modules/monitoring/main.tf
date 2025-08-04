# EC2 CPU utilization
resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  count               = length(var.ec2_instance_ids)
  alarm_name          = "EC2HighCPU-${count.index}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when CPU exceeds 80%"
  dimensions = {
    InstanceId = var.ec2_instance_ids[count.index]
  }
}

# ALB healthy host count
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "ALB-Unhealthy-Targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Fewer than 1 healthy hosts in ALB target group"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

# RDS Free Storage Space
resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "RDS-Low-Free-Storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10000000000 # 10 GB
  alarm_description   = "Available RDS storage below 10GB"
  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
}
