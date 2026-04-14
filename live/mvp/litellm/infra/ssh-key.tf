resource "tls_private_key" "ec2_ssh" {
  count = var.generate_ssh_key_pair ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  count = var.generate_ssh_key_pair ? 1 : 0

  key_name   = "${var.name}-ec2"
  public_key = tls_private_key.ec2_ssh[0].public_key_openssh
}

resource "local_sensitive_file" "ssh_private_pem" {
  count = var.generate_ssh_key_pair ? 1 : 0

  filename        = "${path.module}/../${var.name}-ec2.pem"
  content         = tls_private_key.ec2_ssh[0].private_key_pem
  file_permission = "0600"
}
