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
  keyname = "saige-streaming"
}

# data "aws_security_group" "saige_streaming_sg" {
#   filter {
#     name = "group-name"
#     values = ["saige-streaming-sg"]
#   }
# }

# data "aws_subnets" "saige_private_subnet_1" {
#   filter {
#     name = "tag:Name"
#     values = ["Private Subnet 1"]
#   }
# }

# data "aws_subnets" "saige_private_subnet_2" {
#   filter {
#     name = "tag:Name"
#     values = ["Private Subnet 2"]
#   }
# }

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

locals {
  snapshot_map = {
    "us-east-1a" = "snap-074eab5394bf871be"
    "us-east-1b" = "snap-0808baf1ee79b219e"
    "us-east-1c" = "snap-02617744ffff5f916"
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
 
resource "aws_volume_attachment" "saige_streaming" {
  device_name = "/dev/sdf"
  volume_id   = values(aws_ebs_volume.saige_streaming)[0].id
  instance_id = values(aws_instance.iac_instance)[0].id
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
resource "aws_network_interface" "iac-network-interface_A" { 
  subnet_id = var.private_subnet_A
  security_groups = [aws_security_group.saige_streaming_sg.id]
  # attachment {
  #   device_index = 0
  #   instance = aws_instance.iac_instance[0].id
  # }
}

resource "aws_network_interface" "iac-network-interface_B" { 
  subnet_id = var.private_subnet_B
  security_groups = [aws_security_group.saige_streaming_sg.id]
  #   attachment {
  #   device_index = 0
  #   instance = aws_instance.iac_instance[1].id
  # }
}

data aws_ebs_volumes "saige_streaming" {
  
  filter {
    name = "tag:Name"
    values = ["Saige_Streaming_*"]
  }
}

resource "aws_launch_template" "iac-template" {
  name = "iac-template"
  image_id = local.ami
  instance_type = local.instance_type
  key_name = local.keyname
  # user_data = base64encode(templatefile("${path.module}/init_script.tpl", {}))
  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_instance_profile.name
  }
  # network_interfaces {
  #   device_index = 0
  #   network_interface_id = aws_network_interface.iac-network-interface.id    
  # } 
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.saige_vpc.id]
  }

  filter {
    name   = "tag:Name"
    values = ["Private*"]
  }
}


resource "aws_instance" "iac_instance" {
  ami = local.ami
  for_each = toset(data.aws_subnets.private.ids)
  subnet_id = each.key
  launch_template {
    id = aws_launch_template.iac-template.id
    version = "$Latest"
  }

   tags = {
      Name = format("kafka-stream-%s", each.key)
   }
}

resource "aws_spot_instance_request" "iac-spot" {
  spot_price = "0.40"
  ami = local.ami
  instance_type = local.instance_type
  key_name = local.keyname
  security_groups = [aws_security_group.saige_streaming_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  subnet_id = var.private_subnet_A
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
