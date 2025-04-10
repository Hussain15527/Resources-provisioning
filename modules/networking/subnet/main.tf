resource "aws_subnet" "subnet" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${var.project_name}-${var.subnet_type}-subnet"
  }
}
