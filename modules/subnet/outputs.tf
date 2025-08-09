output "subnet_id" {
    value = aws_subnet.subnet1[*].id
  
}