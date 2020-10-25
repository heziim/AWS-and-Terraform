resource "tls_private_key" "hw2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "hw2_key" {
  key_name   = "hw2_key"
  public_key = tls_private_key.hw2_key.public_key_openssh
}

resource "local_file" "hw2_key" {
  sensitive_content  = tls_private_key.hw2_key.private_key_pem
  filename           = "hw2_key.pem"
}
