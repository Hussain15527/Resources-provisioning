variable "subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.0.0/25"
}

variable "project_name" {
  description = "Name of the project (passed from root)"
  type        = string
}

variable "availability_zone" {
  description = "Availability Zone (passed from root)"
  type        = string
}

variable "vpc_id" {
    type = string
}

variable "subnet_type"{
    type = string
}