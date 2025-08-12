resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public["0"].id
  key_name                    = var.ssh_key_name
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  tags = {
    Name    = "${var.project_name}-bastion"
    Project = var.project_name
  }
}