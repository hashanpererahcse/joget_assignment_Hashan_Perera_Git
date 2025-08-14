resource "aws_launch_template" "web" {
  name_prefix            = "${var.project_name}-lt-"
  image_id               = data.aws_ami.al2.id
  instance_type          = "t3.micro"
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  update_default_version = true
  iam_instance_profile {
  name = aws_iam_instance_profile.web.name
}


  tag_specifications {
    resource_type = "instance"
    tags          = { Role = "web", Project = var.project_name }
  }

  # optional but good practice:
  # metadata_options { http_tokens = "required" }
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
  name_prefix = "${substr(var.project_name, 0, 4)}-"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id
  port        = 80 # was 8080
  protocol    = "HTTP"

  health_check {
    path                = "/jw/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
    # (health check port defaults to traffic-port = 80)
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  lifecycle { create_before_destroy = true }
}

# Listener stays on 80 → forwards to the updated TG
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}
