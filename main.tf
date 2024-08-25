resource "aws_vpc" "main" {     ## VPC creation
  cidr_block = var.vpc_cidr
  tags = {
    Name = "my_vpc"
  }
}

resource "aws_subnet" "sub1" {    ## Public Subnet creation
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = var.AZ1
  map_public_ip_on_launch = true ##Instances launched in this subent will have a public IP
  tags = {
    Name = "sub1"
  }

}

resource "aws_subnet" "sub2" {    ## Public Subnet creation
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.AZ2
  map_public_ip_on_launch = true ##Instances launched in this subent will have a public IP
  tags = {
    Name = "sub2"
  }

}

resource "aws_internet_gateway" "igw" { ##attaching internet gateway to vpc for public access of servcies
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "my_igw"
  }
}

resource "aws_route_table" "rt" { ## attaching route tables to subnet to route the traffic
  vpc_id = aws_vpc.main.id        ## This basically provides internet connection to the igw
  route {
    cidr_block = "0.0.0.0/0" ## The route table has the destination as the igw and we will atatch the igw to the public subnets
    gateway_id = aws_internet_gateway.igw.id
  }

}

resource "aws_route_table_association" "rta1" { ## route table association with subnet1
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rta2" { ## route table association with subnet2
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_vpc" "mainvpc" {
  cidr_block = "10.1.0.0/16"
}

resource "aws_security_group" "my_sg" {   ##security group creation
  vpc_id = aws_vpc.main.id
  name   = "websg"
  ingress {                               ## allows HTTP/SSH connection into the VPC from anywhere
    description = "HTTP connection"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    description = "SSH connection"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]

  }

  egress { ## egress connection to anywhere from the VPC
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "websg"
  }

}

resource "aws_s3_bucket" "my-bucket" {        ##bucket creation
  bucket = "sarthak-mamgains-tf-test-bucket"
}

resource "aws_instance" "webserver1" {              ## EC2 instance creation by assocating VPC,subnets and provding an role and userdata to run while creation
  ami                    = "ami-04a81a99f5ec58529"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.my_sg.id]
  subnet_id              = aws_subnet.sub1.id
  user_data              = base64encode(file("user_data.sh"))
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
}

resource "aws_instance" "webserver2" {             ## EC2 instance creation by assocating VPC,subnets and provding an role and userdata to run while creation
  ami                    = "ami-04a81a99f5ec58529"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.my_sg.id]
  subnet_id              = aws_subnet.sub2.id
  user_data              = base64encode(file("user_data1.sh"))
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
}

resource "aws_lb" "my-alb" {                      ## load balancer creation and associating SG and subnets
  name               = "test-alb-tf"
  internal           = false ## load balancer access will be public
  load_balancer_type = "application"
  security_groups    = [aws_security_group.my_sg.id]
  subnets            = [aws_subnet.sub1.id, aws_subnet.sub2.id]

  tags = {
    Name = "Web"
  }
}

resource "aws_lb_target_group" "my-tg" {      ## creating target groups for the load balancer to load the trrafic to the EC2 instances
  name     = "my-project-targetgroups"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {                            ## This insures to do a healthcheck prior to sending trrafic
    path = "/"
    port = "traffic-port"

  }
}

resource "aws_lb_target_group_attachment" "Attach1" {         ## Attching the load balncer to the EC2 instance
  target_group_arn = aws_lb_target_group.my-tg.arn
  target_id        = aws_instance.webserver1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "Attach2" {       ## Attching the load balncer to the EC2 instance
  target_group_arn = aws_lb_target_group.my-tg.arn
  target_id        = aws_instance.webserver2.id
  port             = 80
}

resource "aws_lb_listener" "Listener" {                     ## creating the listening rules for the LB, only on port 80 and HTTP connections will be send forward from the load balancer
  load_balancer_arn = aws_lb.my-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my-tg.arn
  }
}

output "loadbalancerdns" {
  value = aws_lb.my-alb.dns_name
}

# Create IAM role
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policy to IAM role
resource "aws_iam_role_policy" "ec2_role_policy" {
  name   = "ec2_role_policy"
  role   = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = [
          "arn:aws:s3:::sarthak-mamgains-tf-test-bucket",
          "arn:aws:s3:::sarthak-mamgains-tf-test-bucket/*"
        ]
      }
    ]
  })
}

# Create an instance profile for the IAM role               ## This will allow anything created in the EC2 instance will be kept in the S3 bucket
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}