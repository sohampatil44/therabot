output "aws_lb_target_group_arn" {
  value = aws_lb_target_group.therabot_tg.arn
  
}

output "aws_lb_target_group_arn_suffix" {
    value = aws_lb_target_group.therabot_tg.arn_suffix
}

output "aws_lb_arn_suffix" {
    value = aws_lb.therabot_lb.arn_suffix
  
}