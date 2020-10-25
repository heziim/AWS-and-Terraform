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

resource "aws_vpc" "main_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "main_vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main Internet GW"
  }
}


data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private" {
  count = 2
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = "10.0.${1+count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "PrivateSubnet"
  }
}

resource "aws_subnet" "public" {
  count = 2
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = "10.0.${101+count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "PublicSubnet"
  }
}


resource "aws_eip" "nat" {
  count = 2
  vpc = true
}

resource "aws_nat_gateway" "natgw" {
  count = 2
  allocation_id = aws_eip.nat.*.id[count.index]
  subnet_id     = aws_subnet.public.*.id[count.index]
  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "NAT gw"
  }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
}
}

resource "aws_route_table_association" "public_a" {
  count = 2
  subnet_id      = aws_subnet.public.*.id[count.index]
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count =2
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw.*.id[count.index]
}
}

resource "aws_route_table_association" "private_a" {
  count = 2
  subnet_id      = aws_subnet.private.*.id[count.index]
  route_table_id = aws_route_table.private.*.id[count.index]
}

resource "aws_instance" "web_servers" {
  count = 2
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  associate_public_ip_address = true
  subnet_id = aws_subnet.public.*.id[count.index]
  key_name = aws_key_pair.hw2_key.key_name
  depends_on = [aws_internet_gateway.igw]
  vpc_security_group_ids = [aws_security_group.allow_http.id]
  tags = {
    Name = "web-server${count.index}"
  }
user_data = <<-EOF
#! /bin/bash
sudo apt-get update
sudo apt-get install -y nginx
sudo systemctl start nginx 
EOF
}


resource "aws_instance" "db_servers" {
  count = 2
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  #associate_public_ip_address = true
  subnet_id = aws_subnet.private.*.id[count.index]
  key_name = aws_key_pair.hw2_key.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  tags = {
    Name = "db-server${count.index}"
  }
}




resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow Http inbound traffic"
  vpc_id      = aws_vpc.main_vpc.id

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
  vpc_id      = aws_vpc.main_vpc.id

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
  #availability_zones = [data.aws_availability_zones.available.names[1], data.aws_availability_zones.available.names[0]]

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
  subnets = [aws_subnet.public.*.id[0], aws_subnet.public.*.id[1]]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "main lb"
  }
}

