variable "key_name" {}
variable "private_key_path" {}
variable "region" {
  default = "us-east-2"
} 

provider "aws" {
  shared_credentials_file = "/home/hezi/.aws/credentials"
  region = var.region
}

resource "aws_default_vpc" "default" {

}

resource "aws_security_group" "allow_http" {
  description = "Allow port 80 for nginx"
  vpc_id = aws_default_vpc.default.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ops_nginx" {
  ami = "ami-0a54aef4ef3b5f881" 
  instance_type = "t2.medium"
  key_name = var.key_name
  vpc_security_group_ids = [aws_security_group.allow_http.id]
  count = 2


  root_block_device {
    volume_type           = "gp2"
    volume_size           = 10
    delete_on_termination = true
  }

  ebs_block_device {
    device_name = "/dev/sdk"
    volume_type = "gp2"
    volume_size = 10
    encrypted = true
    delete_on_termination = true
  }    

  tags = {
    Name = "ops_nginx"
    Owner = "Hezi Ismah Moshe"
    Purpose = "learning"
  }
  
  connection {
    type = "ssh"
    host = self.public_ip
    user = "ec2-user"
    private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = "set_nginx.sh"
    destination = "/tmp/set_nginx.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/set_nginx.sh",
      "/tmp/set_nginx.sh",
    ]
  }
}


output "aws_instance_public_ip" {
  value = [aws_instance.ops_nginx[0].public_ip, aws_instance.ops_nginx[1].public_ip]
}
