resource "aws_instance" "app" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99" # Ubuntu 20.04
  instance_type = "t2.micro"
  subnet_id     = var.public_subnet_ids[count.index]
  key_name      = var.key_name

  vpc_security_group_ids = [var.ec2_sg_id]
  user_data              = file("${path.module}/user_data.sh")

  tags = {
    Name = "${var.project_name}-app-${count.index}"
  }
}

resource "aws_lb" "app_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "tg" {
  name        = "${var.project_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_lb_target_group_attachment" "attachments" {
  count            = 2
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app[count.index].id
  port             = 8080
}
