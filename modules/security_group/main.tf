resource "aws_security_group" "allow_web_ssh" {
    name = "allow_web_ssh"
    description = "Allow ssh and http"
    vpc_id = var.vpc_id


    ingress {
  description = "Allow SSH from my IP"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"] # Your public IP here
}

    ingress {
        description = "http from anywhere"
        from_port = 8000
        to_port = 8000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        description = "for grafana port"
        from_port = 3000
        to_port = 3000
        protocol =  "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        description = "Allow all outbound traffic"
        from_port = 0
        to_port = 0
        protocol = "-1" # -1 means all protocols
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "Allow k3s server communication"
        from_port = 6443
        to_port = 6443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "Allow NodePort range"
        from_port = 30000
        to_port = 32767
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    #flannel vxlan port
    ingress {
        description = "Allow flannel vxlan port"
        from_port = 8472
        to_port = 8472
        protocol = "udp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 5000
        to_port = 5000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 30080
        to_port = 30080
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
      Name = "therabot-sg"
    }



    
  
}