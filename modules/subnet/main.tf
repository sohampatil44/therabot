resource "aws_subnet" "subnet1" {
    count = length(var.availability_zones)
    vpc_id = var.vpc_id
    cidr_block = cidrsubnet(var.vpc_cidr,8,count.index)
    availability_zone = var.availability_zones[count.index]
    map_public_ip_on_launch = true


    tags = {
      Name = "public-subnet-${count.index}"
    }
  
}