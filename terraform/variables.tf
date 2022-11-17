variable "profile" {
  default = "default"
}
variable "region" {
  default = "eu-north-1"
}

variable "account_id" {
  default = "123455667677"
}
variable "environment" {
  default = "dev"
}
variable "project_name" {
  default = "todos"
}

provider "aws" {
  profile = var.profile
  region  = var.region
}
