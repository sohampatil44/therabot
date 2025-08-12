output "aws_lb_target_group_arn" {
  value = aws_lb_target_group.therabot_tg.arn
  
}

output "aws_lb_target_group_arn_suffix" {
    value = aws_lb_target_group.therabot_tg.arn_suffix
}

output "aws_lb_arn_suffix" {
    value = aws_lb.therabot_lb.arn_suffix
  
}

output "alb_sg_id" {
    value = aws_security_group.alb_sg.id
  
}