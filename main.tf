provider "aws" {
  region = "us-east-1"
}

variable "environment" {
  description = "Setting up for kafka testing and integration"
  type        = string
  default     = "dev"
}

resource "aws_default_vpc" "saige-vpc" {}

locals {
  name   = "saige-streaming"
  ami = var.streaming_ami
  instance_type = var.streaming_type
  subnet_A = var.private_subnet_A
  subnet_B = var.private_subnet_B
  keyname = "saige-streaming"
}

# data "aws_security_group" "saige_streaming_sg" {
#   filter {
#     name = "group-name"
#     values = ["saige-streaming-sg"]
#   }
# }

data "aws_subnets" "saige_private_subnet_1" {
  filter {
    name = "tag:Name"
    values = ["Private Subnet 1"]
  }
}

data "aws_subnets" "saige_private_subnet_2" {
  filter {
    name = "tag:Name"
    values = ["Private Subnet 2"]
  }
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

resource "aws_network_interface" "iac-network-interface_A" { 
  subnet_id = local.subnet_A
  security_groups = [aws_security_group.saige_streaming_sg.id]
  # attachment {
  #   device_index = 0
  #   instance = aws_instance.iac-instance[0].id
  # }
}

# resource "aws_network_interface" "iac-network-interface_B" { 
#   subnet_id = local.subnet_B
#   security_groups = [aws_security_group.saige_streaming_sg.id]
#     attachment {
#     device_index = 0
#     instance = aws_instance.iac-instance[1].id
#   }
# }

# output "aws_network_interface"  {
#   value = data.aws_subnets.saige_vpc_subnet.ids[1]
# }

data "aws_vpc" "saige_vpc" {
  filter {
    name = "tag:Name"
    values = ["saige-vpc"]
  }
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

data "aws_ebs_volume" "Kafka_on_the_Beach" {
  most_recent = true
  filter {
    name = "tag:Name"
    values = ["Kafka on the Beach"]
  }
}

output "Kafka_on_the_Beach" {
  value = data.aws_ebs_volume.Kafka_on_the_Beach.id
}

resource aws_ebs_volume "saige_streaming_A" {
  availability_zone = "us-east-1a"
  size = 50
  type = "gp2"
  encrypted = true
  snapshot_id = "snap-074eab5394bf871be"
  tags = {
    Name = "Saige_Streaming_A"
  }
}
 
resource aws_ebs_volume "saige_streaming_B" {
  availability_zone = "us-east-1b"
  size = 50
  type = "gp2"
  encrypted = true
  snapshot_id = "snap-0808baf1ee79b219e"
  tags = {
    Name = "Saige_Streaming_B"
  }
}

resource "aws_volume_attachment" "iac-prod" {
  device_name = "/dev/sdf"
  volume_id   = data.aws_ebs_volume.Kafka_on_the_Beach.id
  instance_id =  aws_instance.iac-instance[0].id
  count = var.environment == "prod" ? 1:0
}

# resource "aws_volume_attachment" "iac-spot" {
#   device_name = "/dev/sdf"
#   volume_id   = data.aws_ebs_volume.Kafka_on_the_Beach.id
#   instance_id = aws_spot_instance_request.developer-spot[0].spot_instance_id
#  count = var.environment == "prod" ? 0:1
#   depends_on = [
#     aws_spot_instance_request.developer-spot
#   ]
# }

resource "aws_launch_template" "iac-template" {
  name = "iac-template"
  image_id = local.ami
  instance_type = local.instance_type
  key_name = local.keyname
  user_data = base64encode(templatefile("${path.module}/init_script.tpl", {}))
  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_instance_profile.name
  }
  # network_interfaces {
  #   device_index = 0
  #   network_interface_id = aws_network_interface.iac-network-interface.id    
  # } 
}

resource "aws_instance" "iac-instance" {
  ami = local.ami
  count = var.environment == "prod" ? var.server_cnt:0
 
  launch_template {
    id = aws_launch_template.iac-template.id
    version = "$Latest"
  }

   tags = {
      Name = format("kafka-stream-%d", count.index + 1)
   }
}

resource "aws_spot_instance_request" "iac-spot" {
  spot_price = "0.40"
  ami = local.ami
  instance_type = local.instance_type
  key_name = local.keyname
  security_groups = [aws_security_group.saige_streaming_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  subnet_id = local.subnet_A
  count = var.environment == "prod" ? 0:1
  wait_for_fulfillment = true
  user_data = base64encode(templatefile("${path.module}/init_script.tpl", {}))
} 

resource "aws_ec2_tag" "iac-spot-tag" {
    resource_id = aws_spot_instance_request.iac-spot[0].spot_instance_id
    count = var.environment == "prod" ? 0:1
    key = "Name"
    value = "Spot Streaming"
}


# install a bastion host
resource "aws_instance" "bastion-host" {
  ami = var.bastion_ami
  instance_type = var.bastion_type
  subnet_id = var.public_subnet_A
  security_groups = [aws_security_group.saige_streaming_sg.id]
  key_name = "saige-dev"
  associate_public_ip_address = true
  # count = var.environment == "bastion" ? 1:0
   tags = {
      Name = "Bastion Host"
  }
}

output "bastion-host" {
  value = aws_instance.bastion-host.public_dns

  depends_on = [
    aws_instance.bastion-host
  ]
}

# output "iac-spot" {
#   value = coalesce(aws_spot_instance_request.iac-spot[*].spot_instance_id)
  
#   depends_on = [
#     aws_spot_instance_request.iac-spot
#   ]
# }

# output "developer-instance" {
#   value = aws_instance.developer-instance[0].id

#   depends_on = [
#     aws_instance.developer-instance
#   ]
# }
