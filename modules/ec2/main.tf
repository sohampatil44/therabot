resource "aws_instance" "ec21" {
  ami                         = var.ami_id
  instance_type              = var.instance_type
  subnet_id                  = var.subnet_id
  vpc_security_group_ids     = [var.security_group_id]
  key_name                   = var.key_name
  associate_public_ip_address = true
  monitoring                 = true  # ✅ Enable CloudWatch monitoring
  iam_instance_profile = aws_iam_instance_profile.cw_instance_profile.name
  
  
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

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.cw_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
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
          "cloudwatch:GetMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "cloudwatch:DescribeAlarms"

        ],
        Resource = "*"
      },
      
    ]
  })
  
}


#CLOUDWATCH LOG GROUP CREATION------------------
#-----------------------------------------------

resource "aws_cloudwatch_log_group" "system_log" {
  name = "therabot-system-log"
  retention_in_days = 30
  
}
resource "aws_cloudwatch_log_group" "docker_logs" {
  name = "therabot-docker-logs"
  retention_in_days = 30
  
}

resource "aws_cloudwatch_metric_alarm" "therabot_cpu_alarm" {
  alarm_name = "TherabotHighCPU"
  comparison_operator = "GreaterThanThreshold"
  threshold = "70"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  alarm_description = "This metric monitors EC2 CPU utilization for Therabot"
  dimensions = {
    InstanceId = aws_instance.ec21.id
  }
  actions_enabled = false
  
}

resource "aws_cloudwatch_metric_alarm" "high_request_alarm" {
  alarm_name = "TherabotHighRequestCount"
  comparison_operator = "GreaterThanThreshold"
  threshold = "100"
  alarm_description = "High number of requests per target,scale out"
  evaluation_periods = 2
  metric_name = "RequestCountPerTarget"
  namespace = "AWS/ApplicationELB"
  period = 60
  statistic = "Average"
  dimensions = {
    TargetGroup = var.therabot_arn_suffix
    LoadBalancer = var.lb_suffix
  }

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
  
}
resource "aws_cloudwatch_metric_alarm" "low_request_alarm" {
  alarm_name = "TherabotLowRequestCount"
  comparison_operator = "LessThanThreshold"
  threshold = 10
  evaluation_periods = 2
  metric_name = "RequestCountPerTarget"
  namespace = "AWS/ApplicationELB"
  period = 60
  statistic = "Average"
  alarm_description = "Low request count, scale in"
  dimensions = {
    TargetGroup= var.therabot_arn_suffix
    LoadBalancer = var.lb_suffix
  }
  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
  
}

resource "aws_iam_role_policy_attachment" "attach_custom_policy" {
  role       = aws_iam_role.cw_role.name
  policy_arn = aws_iam_policy.custom_cw_policy.arn
  
}

#ASG LAUNCH TEMPLATE CREATION

resource "aws_launch_template" "therabot_template" {
  name_prefix = "therabot-"
  image_id = var.ami_id
  instance_type = var.instance_type

  key_name = var.key_name
  user_data = base64encode(file("${path.module}/../user_data.sh"))
  iam_instance_profile {
    name = aws_iam_instance_profile.cw_instance_profile.name
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups = [var.security_group_id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 32
      volume_type = "gp3"
    }
  }
  
}

resource "aws_autoscaling_group" "therabot_asg" {
  desired_capacity = 1
  max_size = 3
  min_size = 1
  vpc_zone_identifier = [var.subnet_id]
  health_check_type = "ELB"
  target_group_arns = [var.target_group_arn]
  launch_template {
    id = aws_launch_template.therabot_template.id
    version = "$Latest"

  }
  tag {
    key = "Name"
    value = "therabot-asg"
    propagate_at_launch = true
  }
  
  
  
}

resource "aws_autoscaling_policy" "scale_out" {
  name = "scale-out"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.therabot_asg.name
  
}

resource "aws_autoscaling_policy" "scale_in" {
  name = "scale-in"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.therabot_asg.name
  
}

resource "aws_cloudwatch_event_rule" "asg_events" {
  name = "asg-scaling-events"
  description = "Rule to capture ASG scaling events"
  event_pattern = jsonencode({
    "source": ["aws.autoscaling"],
    "detail-type": [
      "EC2 Instance-launch Lifecycle Action",
    "EC2 Instance-terminate Lifecycle Action",
    "EC2 Instance-launch Successful",
    "EC2 Instance-terminate Successful",
    "EC2 Instance-launch Failed",
    "EC2 Instance-terminate Failed",
    "Auto Scaling EC2 Instance Launch Lifecycle Action",
    "Auto Scaling EC2 Instance Terminate Lifecycle Action",
    "Auto Scaling EC2 Instance Launch Successful",
    "Auto Scaling EC2 Instance Terminate Successful",
    "Auto Scaling EC2 Instance Launch Failed",
    "Auto Scaling EC2 Instance Terminate Failed"
    ]
  })
  
}

resource "aws_cloudwatch_event_target" "sns_target" {
  rule = aws_cloudwatch_event_rule.asg_events.name
  arn = aws_sns_topic.asg_notifications.arn
  target_id = "sns-topc"
  
}
resource "aws_sns_topic" "asg_notifications" {
  name = "asg-notifications"
  
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.asg_notifications.arn
  protocol = "email"
  endpoint = "hydrogen939@gmail.com"
  
}