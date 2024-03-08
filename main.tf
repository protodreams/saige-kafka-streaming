provider "aws" {
  region = "us-east-1"
}

variable "environment" {
  description = "Setting up for kafka testing and integration"
  type        = string
  default     = "dev"
}

locals {
  name   = "saige-streaming"
  ami = var.streaming_ami
  instance_type = var.streaming_type
  keyname = "saige-streaming"
}

data "aws_vpc" "saige_vpc" {
  filter {
    name = "tag:Name"
    values = ["saige-vpc"]
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.saige_vpc.id]
  }

   tags = {
    Name = "Private Subnet*"
  }
}
 
output "private_subnets" {
  value = data.aws_subnets.private_subnets.ids
}

locals {
  private_subnet_map = [for subnet in data.aws_subnets.private_subnets : {
    subnet_id = subnet
  }]
}

output "private_subnet_map" {
  value = local.private_subnet_map
}

data "aws_subnet" "private_subnet" {
  vpc_id     = data.aws_vpc.saige_vpc.id
  for_each = toset(data.aws_subnets.private_subnets.ids)
  id = each.value
} 

locals {
  subnet_azs = { for s in data.aws_subnet.private_subnet : s.id => s.availability_zone }
}
  
output "subnet_azs" {
  value = local.subnet_azs
}

resource "aws_iam_role" "saige_streaming_ssm_role" {
  name = "saige-streaming-ssm-role"

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

resource "aws_iam_role_policy_attachment" "streaming_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.saige_streaming_ssm_role.name
}

resource "aws_security_group" "saige_streaming_sg" {
  name        = "saige-streaming-sg"
  description = "Security group for saige streaming on kafka instances"
  vpc_id      = data.aws_vpc.saige_vpc.id

  dynamic ingress {
    for_each = var.ingress_ports
    content {
    from_port   = ingress.value.from_port
    to_port     = ingress.value.to_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "saige-streaming-sg"
  }
}

output "saige_streaming_sg_id" {
  value = aws_security_group.saige_streaming_sg.id
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
    name = "ssm-instance-profile"
    role = aws_iam_role.saige_streaming_ssm_role.name
  }

locals {
  snapshot_map = {
    "us-east-1a" = var.vol_snapshot
    "us-east-1b" = var.vol_snapshot
    "us-east-1c" = var.vol_snapshot
  }
}

resource aws_ebs_volume "saige_streaming" {
  for_each = {for idx, name in local.snapshot_map: idx => name}
  availability_zone = each.key
  size = 50
  type = "gp2"
  encrypted = true
  snapshot_id = each.value
  tags = {
    Name = format("Saige-Streaming-%s", each.value)
  }
}

output "saige_streaming_volume_id" {
  value = values(aws_ebs_volume.saige_streaming)[0].id
}

locals {
  volume_map = {
    tostring(values(aws_ebs_volume.saige_streaming)[0].availability_zone) = values(aws_ebs_volume.saige_streaming)[0].id
    tostring(values(aws_ebs_volume.saige_streaming)[1].availability_zone) = values(aws_ebs_volume.saige_streaming)[1].id
    tostring(values(aws_ebs_volume.saige_streaming)[2].availability_zone) = values(aws_ebs_volume.saige_streaming)[2].id
  }
}

resource "aws_volume_attachment" "saige_streaming" {
  for_each = aws_spot_instance_request.iac_spot
  device_name = "/dev/sdf"
  volume_id = lookup(local.volume_map, tostring(each.value.availability_zone))
  instance_id = each.value.spot_instance_id

  depends_on = [
    aws_spot_instance_request.iac_spot
  ]
}
resource "aws_launch_template" "iac_template" {
  name = "iac_template"
  image_id = local.ami
  instance_type = local.instance_type
  key_name = local.keyname
  user_data = base64encode(templatefile("${path.module}/init_script.yaml", {}))
  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_instance_profile.name
  }
}

resource "aws_spot_instance_request" "iac_spot" {
  spot_price = "0.10"
  ami = local.ami
  for_each = toset(data.aws_subnets.private_subnets.ids) 
  subnet_id = each.key
  availability_zone = lookup(local.subnet_azs, each.key)

  instance_type = local.instance_type
  key_name = local.keyname
  security_groups = [aws_security_group.saige_streaming_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  wait_for_fulfillment = true
  user_data = base64encode(templatefile("${path.module}/init_script.tpl", {}))
} 

resource "aws_ec2_tag" "iac_spot_tag" {
    for_each = aws_spot_instance_request.iac_spot
    resource_id = each.value.spot_instance_id
    key = "Name"
    value = format("Kafka %s", index(keys(aws_spot_instance_request.iac_spot), each.key) + 1)

    depends_on = [
      aws_spot_instance_request.iac_spot
    ]
}
