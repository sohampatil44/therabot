resource "aws_lb" "therabot_lb" {
    name = "therabot-alb"
    internal = false
    load_balancer_type = "application"
    security_groups = [var.alb_sg_id]
    subnets = var.public_subnets

    enable_deletion_protection = false

    access_logs {
      bucket = aws_s3_bucket.alb_logs_bucket.id
      prefix = "alb-access-logs"
      enabled = true
    }
  
}

resource "aws_lb_target_group" "therabot_tg" {
    name = "therabot-tg"
    port = 8000
    protocol = "HTTP"
    vpc_id = var.vpc_id
    target_type = "instance"

    health_check {
      path = "/"
      interval = 30
      timeout = 5
      healthy_threshold = 5
      unhealthy_threshold = 2
      matcher = "200"
    }
  
}

resource "aws_lb_listener" "http_listener" {
    load_balancer_arn = aws_lb.therabot_lb.arn
    port  = 80
    protocol = "HTTP"

    default_action {
      type = "forward"
      target_group_arn = aws_lb_target_group.therabot_tg.arn
    }
  
}

resource "aws_s3_bucket" "alb_logs_bucket" {
  bucket = "therabot-alb-logs-bucket"
  acl = "private"

  versioning {
    enabled = true
  }
  
}


resource "aws_s3_bucket_policy" "name" {
  bucket = aws_s3_bucket.alb_logs_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "AllowALBLogs",
        Effect = "Allow",
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        },
        Action = ["s3:PutObject","s3:PutObjectAcl"],
        Resource = "${aws_s3_bucket.alb_logs_bucket.arn}/alb-access-logs/*"
      },
      {
        Sid = "AllowSSLRequestsOnly",
        Effect = "Deny",
        Principal = "*",
        Action = "s3:*",
        Resource = "${aws_s3_bucket.alb_logs_bucket.arn}/*",
        Condition = {
          Bool = {
          "aws:SecureTransport" = "false"
      }
      }
      }
      
    ]
    
    
  })
  
}