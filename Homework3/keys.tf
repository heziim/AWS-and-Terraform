resource "tls_private_key" "hw3_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "hw3_key" {
  key_name   = "hw3_key"
  public_key = tls_private_key.hw3_key.public_key_openssh
}

resource "local_file" "hw3_key" {
  sensitive_content  = tls_private_key.hw3_key.private_key_pem
  filename           = "hw3_key.pem"
}
