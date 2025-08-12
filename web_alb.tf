# Launch template for web servers (Apache)
locals {
  web_user_data = <<-EOF
              #!/bin/bash
              set -eux
              yum update -y
              yum install -y httpd
              systemctl enable httpd
              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
              cat > /var/www/html/index.html <<EOP
              <html><body style="font-family: sans-serif">
              <h1>Apache is up ✅</h1>
              <p>Instance: $INSTANCE_ID</p>
              <p>AZ: $AZ</p>
              </body></html>
              EOP
              systemctl start httpd
              EOF
}

resource "aws_launch_template" "web" {
  name_prefix            = "${var.project_name}-lt-"
  image_id               = data.aws_ami.al2.id
  instance_type          = "t3.micro"
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(local.web_user_data)

  tag_specifications {
    resource_type = "instance"
    tags          = { Role = "web", Project = var.project_name }
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name                = "${var.project_name}-asg"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.private["0"].id, aws_subnet.private["1"].id]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web_tg.arn]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public["0"].id, aws_subnet.public["1"].id]
  idle_timeout       = 60
  tags               = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}