resource "aws_instance" "ec21" {
  ami                         = var.ami_id
  instance_type              = var.instance_type
  subnet_id                  = var.subnet_id
  vpc_security_group_ids     = [var.security_group_id]
  key_name                   = var.key_name
  associate_public_ip_address = true
  monitoring                 = true  # ✅ Enable CloudWatch monitoring
  iam_instance_profile = aws_iam_instance_profile.cw_instance_profile.name
  
  #for uplaoding provisioning files(eg. datasources.yaml, dashboards.yaml, ec2-dashboard.json)
  provisioner "file" {
    source = "scripts/grafana/provisioning"
    destination = "/home/ec2-user/grafana/"
    
  }
  # execute commands (copy files to /etc/grafana/provisioning/)
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/grafana/provisioning/datasources",
      "sudo mkdir -p /etc/grafana/provisioning/dashboards",
      "sudo mkdir -p /etc/grafana/provisioning/dashboards-json",
      "sudo cp /home/ec2-user/grafana/datasources.yaml /etc/grafana/provisioning/datasources/",
      "sudo cp /home/ec2-user/grafana/dashboards.yaml /etc/grafana/provisioning/dashboards/",
      "sudo cp /home/ec2-user/grafana/dashboards-json/*.json /etc/grafana/provisioning/dashboards-json/"
    ]
  }
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

# CloudWatch IAM ROLE

resource "aws_iam_role" "cw_role" {
  name="EC2CloudWatchRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
  
}

resource "aws_iam_role_policy_attachment" "cw_attach" {
  role = aws_iam_role.cw_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  
}
resource "aws_iam_instance_profile" "cw_instance_profile" {
  name = "EC2CloudWatchInstanceProfile"
  role = aws_iam_role.cw_role.name
  
}

resource "aws_iam_policy" "custom_cw_policy" {
  name = "EC2CustomCloudWatchPolicy"
  description = "Custom policy to allow cloudwatch logs and metrics"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "cloudwatch:PutMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ],
        Resource = "*"
      },
      
    ]
  })
  
}

resource "aws_iam_role_policy_attachment" "attach_custom_policy" {
  role       = aws_iam_role.cw_role.name
  policy_arn = aws_iam_policy.custom_cw_policy.arn
  
}

