resource "aws_route_table" "public" {

    vpc_id = var.vpc_id


    route {
        cidr_block ="0.0.0.0/0" 
        gateway_id = var.igw_id
    }

    tags = {
      Name = "public-rt"
    }
  
}


resource "aws_route_table_association" "a" {
    count = length(var.subnet_id)
    subnet_id = var.subnet_id[count.index]
    route_table_id = aws_route_table.public.id
  
}