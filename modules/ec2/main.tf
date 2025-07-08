resource "aws_instance" "ec21" {
    ami = var.ami_id
    instance_type =var.instance_type
    subnet_id = var.subnet_id
    vpc_security_group_ids = [var.security_group_id]
    key_name= var.key_name
    associate_public_ip_address  = true

    
    user_data  = file("${path.module}/../user_data.sh")
    tags= {
        Name = "ripensense-ec2"
    }

    connection {
        type = "ssh"
        user = "ec2-user"
        private_key = file("/Users/sohampatil/ripensense/RipenSense/network-keypair.pem")
        host = self.public_ip
        timeout = "2m"
    }
   
    
  
}