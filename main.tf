module "vpc"{
    source = "./modules/vpc"
    vpc_cidr = var.vpc_cidr
    env_name = var.env_name
}

module "subnet" {
    source = "./modules/subnet"
    vpc_id = module.vpc.vpc_id
    vpc_cidr = var.vpc_cidr
    env_name = var.env_name
  
}

module "igw" {
    source = "./modules/internet_gw"
    vpc_id = module.vpc.vpc_id
  
}

module "route_table" {
    source = "./modules/route_table"
    vpc_id = module.vpc.vpc_id
    igw_id = module.igw.igw_id
    subnet_id = module.subnet.subnet_id
  
}

module "security_group" {
    source = "./modules/security_group"
    vpc_id = module.vpc.vpc_id
  
}

module "ec2" {
    source = "./modules/ec2"
    ami_id = "ami-08a6efd148b1f7504"
    instance_type = "t3.micro"
    key_name = var.key_name
    security_group_id = module.security_group.security_group_id
    subnet_id = module.subnet.subnet_id
    target_group_arn = module.alb_asg_lb.aws_lb_target_group_arn
    therabot_arn_suffix = module.alb_asg_lb.aws_lb_target_group_arn_suffix
    lb_suffix = module.alb_asg_lb.aws_lb_arn_suffix

    
  
}
module "alb_asg_lb" {
    source = "./modules/alb_asg_lb"
    alb_sg_id = module.security_group.security_group_id
    vpc_id = module.vpc.vpc_id
    public_subnets = module.subnet.subnet_id

    

  
}

output "ec2_public_ip" {
    value = module.ec2.public_ip
  
}