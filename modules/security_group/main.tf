resource "aws_security_group" "allow_web_ssh" {
    name = "allow_web_ssh"
    description = "Allow ssh and http"
    vpc_id = var.vpc_id


    ingress {
        description = "ssh from anywhere"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "http from anywhere"
        from_port = 8000
        to_port = 8000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        description = "Allow all outbound traffic"
        from_port = 0
        to_port = 0
        protocol = "-1" # -1 means all protocols
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
      Name = "ripensense-sg"
    }
  
}