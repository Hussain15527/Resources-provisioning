variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/24"
}



variable "project_name" {
  description = "Name of the project (passed from root)"
  type        = string
}