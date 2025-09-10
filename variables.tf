variable "vpc_cidr" {
  type = string
}

variable "env_name" {
  type = string

}

variable "key_name" {
    type = string
  
}

variable "stage" {
  description = "Deployement stage (dev/prod)"
  type = string
  default = "dev"
  
}
variable "github_token" {
  description = "Github token for repo access"
  type = string
  
}
variable "region" {
  description = "AWS region"
  type = string
  default = "us-east-1"
  
}