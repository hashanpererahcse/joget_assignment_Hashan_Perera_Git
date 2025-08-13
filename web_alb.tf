# Launch template for web servers (Apache)
locals {
  web_user_data = <<EOF
  #!/bin/bash
  set -euxo pipefail

  # Java 11 + tools
  yum update -y
  amazon-linux-extras install -y java-openjdk11 || yum install -y java-11-amazon-corretto-headless -y
  yum install -y curl tar gzip unzip mariadb

  install_dir=/opt/joget
  mkdir -p "$install_dir"
  cd "$install_dir"

  # ----- DB from Terraform -----
  DB_HOST="${aws_db_instance.mysql.address}"
  DB_NAME="${var.db_name}"
  DB_USER="${var.db_username}"
  DB_PASS='${var.db_password}'

  # Wait for DB (up to ~10 min)
  for i in {1..60}; do
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "select 1" >/dev/null 2>&1; then echo "DB is up"; break; fi
    echo "waiting for DB..."; sleep 10
  done

  # Create DB if missing
  mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

  # ----- Download Joget bundle (your direct URL) -----
  curl -L -o joget.tar.gz "https://drive.usercontent.google.com/download?id=1sXTRXAXz-i4_szr3fXiJwjAEp0sNfoFr&export=download&confirm=t&uuid=881e9b97-7277-4c3e-8ba6-6df3886f9106"

  # Sanity check it's a real tar.gz
  if ! tar -tzf joget.tar.gz >/dev/null 2>&1; then
    echo "ERROR: joget.tar.gz is not a valid tar.gz"; exit 1
  fi

  tar -xzf joget.tar.gz

  # Normalize Tomcat dir name: apache-tomcat-* -> apache-tomcat
  if ls $install_dir | grep -q "apache-tomcat-"; then
    TDIR=$(ls -d $install_dir/apache-tomcat-* | head -n1)
    ln -sfn "$TDIR" $install_dir/apache-tomcat
  fi

  # ----- MySQL Connector/J -----
  CJ_VER=8.4.0
  curl -L -o /tmp/mysqlcj.tgz "https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-$${CJ_VER}.tar.gz"
  mkdir -p /tmp/cj && tar -xzf /tmp/mysqlcj.tgz -C /tmp/cj
  CJAR=$(find /tmp/cj -name "mysql-connector-j-*.jar" | head -n1)
  cp "$CJAR" "$install_dir/apache-tomcat/lib/mysql-connector-j.jar"

  # ----- Joget datasource -----
  cat > "$install_dir/wflow.properties" <<EOP
  workflowDriver=com.mysql.cj.jdbc.Driver
  workflowUrl=jdbc:mysql://$DB_HOST:3306/$DB_NAME?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
  workflowUser=$DB_USER
  workflowPassword=$DB_PASS
  currentProfile=default
  setup=true
  EOP

  # ----- systemd service for Joget/Tomcat -----
  cat >/etc/systemd/system/joget.service <<'EOS'
  [Unit]
  Description=Joget (Tomcat) service
  After=network.target
  [Service]
  Type=forking
  Environment=JAVA_HOME=/usr/lib/jvm/jre-11
  Environment=CATALINA_BASE=/opt/joget/apache-tomcat
  Environment=CATALINA_HOME=/opt/joget/apache-tomcat
  Environment=CATALINA_PID=/opt/joget/apache-tomcat/temp/tomcat.pid
  ExecStart=/opt/joget/apache-tomcat/bin/startup.sh
  ExecStop=/opt/joget/apache-tomcat/bin/shutdown.sh
  User=root
  Restart=on-failure
  [Install]
  WantedBy=multi-user.target
  EOS

  systemctl daemon-reload
  systemctl enable joget
  systemctl start joget
  EOF
}


resource "aws_launch_template" "web" {
  name_prefix            = "${var.project_name}-lt-"
  image_id               = data.aws_ami.al2.id
  instance_type          = "t3.micro"
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  update_default_version = true

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
  name_prefix = "${substr(var.project_name, 0, 4)}-"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id
  port        = 8080
  protocol    = "HTTP"

  health_check {
    path                = "/jw/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  # let TF create the new TG before destroying the old one
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