 
 variable server_cnt {
     description = "The number of servers to create"
     type = number
     default = 2
 }
 
 variable "streaming_ami" {
     description = "Streaming platform kafka cluster"
     type = string
     default = "ami-0f93c02efd1974b8b"
 }
 
 variable "streaming_type" {
      description = "The ec2 type for streaming kafka cluster"
      type = string
      default = "t4g.large" 
 }


variable "ingress_ports" {
  description = "The list of ingress ports to allow for kafka with KRaft"
  type        = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
  }))
  default = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
    },
    {
      from_port   = 9092
      to_port     = 9092
      protocol    = "tcp"
    },
    {
      from_port   = 19092
      to_port     = 19092
      protocol    = "tcp"
    }
  ]
}



 variable "private_subnet_A" {
     description = "The subnet for development on private subnet zone A"
     type = string
     default = "subnet-079595242f44b63b3"
 }

 variable "private_subnet_B" {
     description = "The subnet for development on private subnet zone A"
     type = string
     default = "subnet-015c0e5606a890cef"
 }
 
 variable "public_subnet_A" {
     description = "The subnet for bastion on public subnet zone A"
     type = string
     default = "subnet-06f05a3137f77afc6"
 }





