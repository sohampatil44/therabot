resource "aws_instance" "ec21" {
  ami                         = var.ami_id
  instance_type              = var.instance_type
  subnet_id                  = var.subnet_id
  vpc_security_group_ids     = [var.security_group_id]
  key_name                   = var.key_name
  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "unlimited"
  }

  root_block_device {
    volume_size = 32          # ✅ Increased to 32 GB
    volume_type = "gp3"       # ✅ Faster and more cost-effective
  }

  user_data = file("${path.module}/../user_data.sh")

  tags = {
    Name = "therabot-ec2"
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/sohampatil/ripensense/RipenSense/network-keypair.pem")
    host        = self.public_ip
    timeout     = "2m"
  }
}
