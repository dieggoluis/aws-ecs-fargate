variable "AWS_ACCESS_KEY" {}
variable "AWS_SECRET_KEY" {}

variable "AWS_REGION" {
  default = "us-west-1"
}

variable "azs" {
  type    = list
  default = ["us-west-1a", "us-west-1c"]
}

variable "ecs-cluster" {
  type    = string
  default = "ecs-fargate"
}

variable "vpc-name" {
  type    = string
  default = "vpc"
}

variable "vpc-cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public-subnets" {
  type    = list
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private-subnets" {
  type    = list
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "environment" {
  type    = string
  default = "DEV"
}
