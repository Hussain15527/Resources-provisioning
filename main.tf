#vpc
module "vpc" {
  source = "./modules/networking/vpc"

  project_name = var.project_name
  vpc_cidr     = "10.0.0.0/24"
}

# First public subnet
module "public_subnet_1" {
  source = "./modules/networking/subnet"

  vpc_id = module.vpc.id

  subnet_cidr = "10.0.0.0/26"  
  availability_zone  = "ap-south-1a"
  project_name       = module.vpc.project_name
  subnet_type        = "public"
}

# Second public subnet
module "public_subnet_2" {
  source = "./modules/networking/subnet"

  vpc_id = module.vpc.id

  subnet_cidr = "10.0.0.64/26"  
  availability_zone  = "ap-south-1b"
  project_name       = module.vpc.project_name
  subnet_type        = "public"
}

module "private_subnet_app" {
  source = "./modules/networking/subnet"

  vpc_id = module.vpc.id

  subnet_cidr = "10.0.0.128/25"
  availability_zone = "ap-south-1a"
  project_name      = module.vpc.project_name
  subnet_type       = "private"
}


# internet gateway
resource "aws_internet_gateway" "gw" {
 vpc_id = module.vpc.id
 
 tags = {
   Name = "${module.vpc.project_name}-igw"
 }
}

# route table for public subnet
resource "aws_route_table" "public_subnet_route_table" {
 vpc_id = module.vpc.id
 
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }
 
 tags = {
   Name = "${module.vpc.project_name}-public-subnet-route-table"
 }
}

# association for first public subnet
resource "aws_route_table_association" "public_subnet_asso_1" {
  subnet_id      = module.public_subnet_1.id
  route_table_id = aws_route_table.public_subnet_route_table.id
}

# association for second public subnet
resource "aws_route_table_association" "public_subnet_asso_2" {
  subnet_id      = module.public_subnet_2.id
  route_table_id = aws_route_table.public_subnet_route_table.id
}


# security group for application load balancer
resource "aws_security_group" "alb_sg" {
  name        = "${module.vpc.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${module.vpc.project_name}-alb-sg"
  }
}

# security group for EC2 instances
resource "aws_security_group" "app_sg" {
  name        = "${module.vpc.project_name}-app-sg"
  description = "Security group for EC2 instances in ASG"
  vpc_id      = module.vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

    ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${module.vpc.project_name}-app-sg"
  }
}


# application load balancer in the public subnets
resource "aws_lb" "app_lb" {
  name               = "${module.vpc.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [module.public_subnet_1.id, module.public_subnet_2.id]  # Using both subnets

  enable_deletion_protection = false

  tags = {
    Name = "${module.vpc.project_name}-alb"
  }
}


# target group for load balancer
resource "aws_lb_target_group" "app_tg" {
  name     = "${module.vpc.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.id
  
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

# listener for the load balancer
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# NAT Gateway for private subnet internet access
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "${module.vpc.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = module.public_subnet_1.id
  
  tags = {
    Name = "${module.vpc.project_name}-nat-gw"
  }
}

# Route table for private subnet
resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = module.vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  
  tags = {
    Name = "${module.vpc.project_name}-private-subnet-route-table"
  }
}

# Associate private subnet with route table
resource "aws_route_table_association" "private_subnet_asso" {
  subnet_id      = module.private_subnet_app.id
  route_table_id = aws_route_table.private_subnet_route_table.id
}

# launch template for the auto scaling group
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${module.vpc.project_name}-lt-"
  image_id      = "ami-0a0f1259dd1c90938"  # Amazon Linux 2 in ap-south-1, update as needed
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nodejs npm git
    mkdir -p /home/ec2-user/app
    cd /home/ec2-user/app
    git clone https://gitlab.com/your-repo/hello-world-nodejs.git .
    npm install
    node index.js &
    EOF
  )
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${module.vpc.project_name}-app-instance"
    }
  }
}

# auto scaling group
resource "aws_autoscaling_group" "app_asg" {
  name                = "${module.vpc.project_name}-asg"
  max_size            = 3
  min_size            = 1
  desired_capacity    = 2
  vpc_zone_identifier = [module.private_subnet_app.id]
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  health_check_type   = "ELB"
  
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
  
  tag {
    key                 = "Name"
    value               = "${module.vpc.project_name}-app-asg"
    propagate_at_launch = true
  }
}