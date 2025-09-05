resource "aws_lb" "therabot_lb" {
    name = "therabot-alb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb_sg.id]
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
      interval = 60
      timeout = 10
      healthy_threshold = 2
      unhealthy_threshold = 10
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

#_____-----------------__________________-------------------___________
#--------------------------------------------------------------------------
#-----------------------------------------------------------------------------

# S3 BUCKET FOR ALB LOGS
resource "aws_s3_bucket" "alb_logs_bucket" {
  bucket = "therabot-alb-logs-bucket"
}
resource "aws_s3_bucket_versioning" "alb_logs_bucket_versioning" {
  bucket = aws_s3_bucket.alb_logs_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
  
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs_lifecycle" {
  bucket = aws_s3_bucket.alb_logs_bucket.id

  rule {
    id = "ExpireAllVersions"
    status = "Enabled"

    filter {
      prefix = "AWSLogs/"
    }
    noncurrent_version_expiration {
      noncurrent_days  = 1
    }
  }
  
}
resource "null_resource" "empty_alb_logs" {
  triggers = {
    bucket     = aws_s3_bucket.alb_logs_bucket.id
    run_always = timestamp() # Forces this to run every apply
  }

  provisioner "local-exec" {
    command = <<EOT
# Delete all object versions if any exist
versions_json=$(aws s3api list-object-versions \
  --bucket ${aws_s3_bucket.alb_logs_bucket.bucket} \
  --query 'Versions[].{Key:Key,VersionId:VersionId}' \
  --output json)

if [ "$versions_json" != "[]" ]; then
  echo "Deleting object versions..."
  delete_json=$(jq -n --argjson objects "$versions_json" '{Objects: $objects}')
  echo "$delete_json" > /tmp/delete_versions.json

  aws s3api delete-objects \
    --bucket ${aws_s3_bucket.alb_logs_bucket.bucket} \
    --delete file:///tmp/delete_versions.json
fi

# Delete all delete markers if any exist
markers_json=$(aws s3api list-object-versions \
  --bucket ${aws_s3_bucket.alb_logs_bucket.bucket} \
  --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
  --output json)

if [ "$markers_json" != "[]" ]; then
  echo "Deleting delete markers..."
  delete_json=$(jq -n --argjson objects "$markers_json" '{Objects: $objects}')
  echo "$delete_json" > /tmp/delete_markers.json

  aws s3api delete-objects \
    --bucket ${aws_s3_bucket.alb_logs_bucket.bucket} \
    --delete file:///tmp/delete_markers.json
fi

echo "Bucket cleanup completed."
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    aws_s3_bucket.alb_logs_bucket,
    aws_s3_bucket_versioning.alb_logs_bucket_versioning,
    aws_s3_bucket_lifecycle_configuration.alb_logs_lifecycle
  ]
}




resource "aws_s3_bucket_policy" "alb_logs_bucket_policy" {
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
        Action = ["s3:PutObject", "s3:PutObjectAcl"],
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

#SECURITY GROOUPS SPECIALLY FOR ALBS-----
#--------------------------------------------------

resource "aws_security_group" "alb_sg" {
  name = "alb-sg"
  description = "Allow HTTP/HTTPS ATRAFFIC FROM THE WORLD"
  vpc_id = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS from anywhere"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  
  
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}