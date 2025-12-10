provider "aws" {
  region = "us-east-1"
}

# ---------- variables (optional) ----------
variable "key_name" {
  type    = string
  default = "my-key"
}

variable "subnet_id" {
  type    = string
  # Replace with your subnet id or pass via -var
  default = "subnet-0491ca8b1885b7e5e"
}

variable "jenkins_allowed_cidr" {
  type    = string
  default = "0.0.0.0/0" # demo: open to world; production: restrict to Jenkins IP/CIDR
}

# ---------------------------
# Security group
# ---------------------------
resource "aws_security_group" "app_sg" {
  name        = "ansible-app-sg"
  description = "Allow SSH, HTTP, Netdata"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_allowed_cidr]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "netdata"
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

# Data to fetch subnet details (so we can read vpc_id)
data "aws_subnet" "selected" {
  id = var.subnet_id
}

# ---------------------------
# Backend - Ubuntu
# ---------------------------
resource "aws_instance" "backend" {
  ami                         = "ami-0ecb62995f68bb549"  # adjust if needed
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "u21.local"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo hostnamectl set-hostname u21.local
  EOF
}

# ---------------------------
# Frontend - Amazon Linux
# ---------------------------
resource "aws_instance" "frontend" {
  ami                         = "ami-068c0051b15cdb816"  # adjust if needed
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "c8.local"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo hostnamectl set-hostname c8.local

    # append private backend IP to /etc/hosts so frontend can reach backend on private IP
    backend_ip="${aws_instance.backend.private_ip}"
    echo "$backend_ip backend.local" | sudo tee -a /etc/hosts
  EOF

  depends_on = [aws_instance.backend]
}

# ---------------------------
# Inventory file
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
