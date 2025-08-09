data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# NETWORKING
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  for_each = {
    az1 = var.public_subnet_cidrs[0]
    az2 = var.public_subnet_cidrs[1]
  }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.names[(each.key == "az1") ? 0 : 1]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    az1 = var.private_subnet_cidrs[0]
    az2 = var.private_subnet_cidrs[1]
  }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[(each.key == "az1") ? 0 : 1]
  tags = {
    Name = "${var.project}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["az1"].id
  tags          = { Name = "${var.project}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-public-rt" }
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-private-rt" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# SECURITY GROUPS
resource "aws_security_group" "alb_sg" {
  name        = "${var.project}-alb-sg"
  description = "ALB ingress"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb-sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project}-app-sg"
  description = "App instances security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Optional SSH (left commented)
  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = [var.allowed_admin_cidr]
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-app-sg" }
}

resource "aws_security_group" "web_sg" {
  count       = var.create_web_server ? 1 : 0
  name        = "${var.project}-web-sg"
  description = "Standalone Apache web server"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-web-sg" }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project}-rds-sg"
  description = "RDS MySQL access"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MySQL from app_sg"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-rds-sg" }
}

# (PASSWORD)
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!-_@#%"
}

resource "aws_secretsmanager_secret" "db" {
  name        = "${var.project}-db-credentials"
  description = "RDS credentials for ${var.project}"
  kms_key_id  = null # uses AWS-managed key by default
  tags        = { Name = "${var.project}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db_value" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "mysql"
    host     = ""
    port     = 3306
    dbname   = var.db_name
  })
}

# RDS
resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db-subnets"
  subnet_ids = [aws_subnet.private["az1"].id, aws_subnet.private["az2"].id]
  tags       = { Name = "${var.project}-db-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier               = "${var.project}-mysql"
  engine                   = "mysql"
  engine_version           = "8.0"
  instance_class           = "db.t2.micro" # changed to t2.micro for cost efficiency - Free Tier eligible
  allocated_storage        = 20
  db_name                  = var.db_name
  username                 = var.db_username
  password                 = random_password.db_password.result
  db_subnet_group_name     = aws_db_subnet_group.this.name
  vpc_security_group_ids   = [aws_security_group.rds_sg.id]
  storage_encrypted        = true
  delete_automated_backups = false
  backup_retention_period  = 7
  multi_az                 = false
  publicly_accessible      = false
  skip_final_snapshot      = true
  apply_immediately        = true
  tags = { Name = "${var.project}-rds" }
}


resource "aws_secretsmanager_secret_version" "db_value_with_host" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "mysql"
    host     = aws_db_instance.mysql.address
    port     = 3306
    dbname   = var.db_name
  })
  depends_on = [aws_db_instance.mysql]
}

# IAM (EC2 can read ONLY this secret)
data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid = "AllowReadSpecificSecret"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name   = "${var.project}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read.json
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_role" {
  name               = "${var.project}-app-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "attach_secrets_read" {
  role       = aws_iam_role.app_role.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${var.project}-app-profile"
  role = aws_iam_role.app_role.name
}

# ALB + TARGET GROUP + LISTENER
resource "aws_lb" "app_alb" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public["az1"].id, aws_subnet.public["az2"].id]
  tags               = { Name = "${var.project}-alb" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "${var.project}-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id
  health_check {
    enabled             = true
    path                = "/"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
  tags = { Name = "${var.project}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# EC2 – APP INSTANCES (2x)
locals {
  app_user_data = <<-EOF
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y jq awscli java-17-amazon-corretto nmap-ncat

    SECRET_ID="${aws_secretsmanager_secret.db.id}"
    REGION="${var.region}"

    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)
    DB_HOST=$(echo "$SECRET_JSON" | jq -r .host)
    DB_NAME=$(echo "$SECRET_JSON" | jq -r .dbname)

    cat >/opt/app.sh <<'APP'
    #!/bin/bash
    cat <<TXT > /tmp/index.html
    <html><body>
    <h1>Java App Node: $(hostname)</h1>
    <p>DB Host: ${DB_HOST}</p>
    <p>DB Name: ${DB_NAME}</p>
    </body></html>
    while true; do { echo -e "HTTP/1.1 200 OK\\n\\n"; cat /tmp/index.html; } | nc -l -p 8080 -q 1; done
    APP
    chmod +x /opt/app.sh

    cat >/etc/systemd/system/app.service <<'UNIT'
    [Unit]
    Description=Demo Java App placeholder
    After=network-online.target
    [Service]
    ExecStart=/opt/app.sh
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now app.service
  EOF
}

resource "aws_instance" "app" {
  count                       = 2
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type_app
  subnet_id                   = (count.index == 0 ? aws_subnet.public["az1"].id : aws_subnet.public["az2"].id)
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.app_profile.name
  key_name                    = var.key_name
  user_data                   = local.app_user_data

  tags = {
    Name = "${var.project}-app-${count.index}"
    Role = "app"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_lb_target_group_attachment" "app_attach" {
  for_each         = { for idx, inst in aws_instance.app : idx => inst }
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = each.value.id
  port             = 8080
}

# EC2 – OPTIONAL WEB SERVER (Apache)
locals {
  web_user_data = <<-EOF
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y httpd
    systemctl enable --now httpd
    echo "<h1>Standalone Apache Web Server</h1><p>$(hostname)</p>" > /var/www/html/index.html
  EOF
}

resource "aws_instance" "web" {
  count                       = var.create_web_server ? 1 : 0
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type_web
  subnet_id                   = aws_subnet.public["az1"].id
  vpc_security_group_ids      = [aws_security_group.web_sg[0].id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  user_data                   = local.web_user_data

  tags = {
    Name = "${var.project}-web"
    Role = "web"
  }
}
