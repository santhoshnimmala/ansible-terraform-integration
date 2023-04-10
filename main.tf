
###########
#data source 
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Create VPC
resource "aws_vpc" "example" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "nginx-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "nginx-igw"
  }
}

# Create Route Table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "nginx-public-rt"
  }
}

# Create Route for public subnet
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.example.id
}

# Create subnets and associate with route tables
locals {
  subnet_cidrs = var.subnet_cidr_blocks
}

resource "aws_subnet" "example" {
  count = length(local.subnet_cidrs)

  cidr_block = local.subnet_cidrs[count.index]
  vpc_id     = aws_vpc.example.id
  availability_zone = "us-east-1a"

  tags = {
    Name = "nginx-subnet-${count.index+1}"
  }
}

resource "aws_route_table_association" "public" {
  count           = length(aws_subnet.example)
  subnet_id       = aws_subnet.example[count.index].id
  route_table_id  = aws_route_table.public.id
}

# Create security group for the NGINX server
resource "aws_security_group" "nginx" {
  name        = "nginx"
  description = "nginx network traffic"
  vpc_id      = aws_vpc.example.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "80 from anywhere"
    from_port   = 80
    to_port     = 80
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
    Name = "Allow traffic for HTTP"
  }
}

# Deploy NGINX server in one of the subnets
resource "aws_instance" "nginx" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.example[0].id
  key_name      = "key1"
  vpc_security_group_ids = [aws_security_group.nginx.id]

  associate_public_ip_address = true


  tags = {
    Name = "nginx"
  }
}


resource "null_resource" "ansible" {
  depends_on = [aws_instance.nginx]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("key1.pem")
    host        = aws_instance.nginx.public_ip
  }
  provisioner "file" {
    source      = "playbook.yml"
    destination = "/tmp/playbook.yml"
  		   }


  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y ansible",
      "cd /tmp/",
      "sudo ansible-playbook playbook.yml"
    ]
  }
}
