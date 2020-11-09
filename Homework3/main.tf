terraform {
  backend "s3" {
    bucket = "tfhezibucket"
    key    = "tfstate/hw3/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "hw3" {
  backend = "s3"
  config = {
    bucket = "tfhezibucket"
    key    = "tfstate/hw3/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
    region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

module "vpc" {
  source = "./my_modules"
  vpc_name = "hm3-vpc"
  cidr_block = "10.0.0.0/16"
  private_subnets = ["10.0.1.0/24" , "10.0.2.0/24"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
  
}

resource "aws_instance" "web_servers" {
  count = 2
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  associate_public_ip_address = true
  subnet_id = module.vpc.public_subnets_ids[count.index]
  key_name = aws_key_pair.hw3_key.key_name
  #depends_on = module.vpc.internet_gw
  vpc_security_group_ids = [aws_security_group.allow_http.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  tags = {
    Name = "web-server${count.index}"
  }
user_data = <<-EOF
#! /bin/bash
sudo apt-get update
sudo apt-get install -y nginx awscli
hostname | sudo tee -a  /var/www/html/index.nginx-debian.html
sudo systemctl start nginx 
echo "0 * * * * root aws s3 cp /var/log/nginx/access.log  s3://hezinginxlogsb" | sudo tee -a /etc/crontab
EOF
}


resource "aws_instance" "db_servers" {
  count = 2
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id = module.vpc.private_subnets_ids[count.index]
  key_name = aws_key_pair.hw3_key.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  tags = {
    Name = "db-server${count.index}"
  }
}




resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow Http inbound traffic"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
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
    Name = "allow_http"
  }
}
 
resource "aws_security_group" "allow_ssh" {     # for testing
  name        = "allow_ssh"
  description = "Allow ssh internal inbound for testing"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
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
    Name = "allow_ssh"
  }
}

 

resource "aws_elb" "main_lb" {

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = [aws_instance.web_servers.*.id[0], aws_instance.web_servers.*.id[1]]
  security_groups = [aws_security_group.allow_http.id]
  #subnets = [aws_subnet.public.*.id[0], aws_subnet.public.*.id[1]]
  subnets = module.vpc.public_subnets_ids
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "main lb"
  }
}

resource "aws_lb_cookie_stickiness_policy" "sticki" {
  name                     = "lb-stickiness-policy"
  load_balancer            = aws_elb.main_lb.id
  lb_port                  = 80
  cookie_expiration_period = 60
  }

resource "aws_s3_bucket" "hezinginxlogsb" {
  bucket = "hezinginxlogsb"
  tags = {
    Name        = "Nginx logs bucket"
  }
}

