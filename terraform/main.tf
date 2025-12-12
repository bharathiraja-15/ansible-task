provider "aws" {
  region = "eu-north-1"
}

variable "key_name" {
  type    = string
  default = "firstserver"
}

variable "subnet_id" {
  type    = string
  default = "subnet-0d91e8fd1fa2524c9"
}

variable "jenkins_allowed_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

# Fetch VPC ID using subnet
data "aws_subnet" "selected" {
  id = var.subnet_id
}

# ---------------------------
# Security Group
# ---------------------------
resource "aws_security_group" "app_sg" {
  name        = "ansible-app-sg"
  description = "Allow SSH, HTTP, Netdata"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_allowed_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Netdata"
    from_port   = 19999
    to_port     = 19999
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ansible-app-sg"
  }
}

# ---------------------------
# Backend (Ubuntu)
# ---------------------------
resource "aws_instance" "backend" {
  ami                         = "ami-0fa91bc90632c73c9"
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "u21.local"
  }

  user_data = <<EOF
#!/bin/bash
hostnamectl set-hostname u21.local
EOF
}

# ---------------------------
# Frontend (Amazon Linux)
# ---------------------------
resource "aws_instance" "frontend" {
  ami                         = "ami-0b46816ffa1234887"
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "c8.local"
  }

  user_data = <<EOF
#!/bin/bash
hostnamectl set-hostname c8.local
echo "${aws_instance.backend.private_ip} backend.local" >> /etc/hosts
EOF

  depends_on = [aws_instance.backend]
}

# ---------------------------
# Inventory File
# ---------------------------
resource "local_file" "inventory" {
  filename = "${path.module}/inventory.yaml"

  content = <<EOF
[frontend]
${aws_instance.frontend.public_ip} ansible_user=ec2-user ansible_host=${aws_instance.frontend.public_ip}

[backend]
${aws_instance.backend.public_ip} ansible_user=ubuntu ansible_host=${aws_instance.backend.public_ip}
EOF
}

# ---------------------------
# Outputs
# ---------------------------
output "frontend_public_ip" {
  value = aws_instance.frontend.public_ip
}

output "backend_public_ip" {
  value = aws_instance.backend.public_ip
}

output "inventory_path" {
  value = local_file.inventory.filename
}
