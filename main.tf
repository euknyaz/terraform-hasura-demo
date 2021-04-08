provider "aws" {
  region = local.region
}

locals {
  name   = "hasura-tf"
  region = "us-east-1"
  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

################################################################################
# Keypair
################################################################################

resource "tls_private_key" "this" {
  algorithm = "RSA"
}

module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name   = "user1"
  # public_key = tls_private_key.this.public_key_openssh
  public_key = file("keypair.pem.pub")
  create_key_pair = true
}
################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2"

  name = local.name
  cidr = "10.99.0.0/18"

  azs              = ["${local.region}a", "${local.region}b", "${local.region}c"]
  public_subnets   = ["10.99.0.0/24", "10.99.1.0/24", "10.99.2.0/24"]
  private_subnets  = ["10.99.3.0/24", "10.99.4.0/24", "10.99.5.0/24"]
  database_subnets = ["10.99.7.0/24", "10.99.8.0/24", "10.99.9.0/24"]

  create_database_subnet_group = true

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = local.tags
}

################################################################################
# RDS Module
################################################################################

resource "random_password" "hasura_secret" {
  length           = 16
  special          = true
  override_special = "_%@"
}

data "template_cloudinit_config" "config" {
  gzip          = false
  base64_encode = true
  # part 1: .env
  part {
    content_type = "text/x-shellscript"
    content      = <<-EOF
    #!/bin/bash
    echo 'HASURA_GRAPHQL_DATABASE_URL="postgres://${module.db.this_db_instance_username}:${module.db.this_db_instance_password}@${module.db.this_db_instance_endpoint}/${module.db.this_db_instance_name}"' > /home/ec2-user/.env
    echo 'HASURA_GRAPHQL_ADMIN_SECRET="${random_password.hasura_secret.result}"' >> /home/ec2-user/.env
    EOF
  }
  # part 2: init.cfg
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = file("./ec2_cloud.cfg")
  }
}

module "ec2_instance" {
  source                 = "terraform-aws-modules/ec2-instance/aws"
  version                = "~> 2.0"

  name                   = "${local.name}-ec2"
  instance_count         = 1

  ami                    = "ami-0742b4e673072066f" # us-east-1
  # ami                    = "ami-05d72852800cbf29e" # us-east-2
  instance_type          = "t2.micro"
  key_name               = module.key_pair.this_key_pair_key_name
  monitoring             = true
  vpc_security_group_ids = [module.ec2_security_group.this_security_group_id]
  subnet_id              = tolist(module.vpc.public_subnets)[0]

  user_data_base64       = data.template_cloudinit_config.config.rendered

  associate_public_ip_address = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "ec2_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "example"
  description = "Security group for example usage with EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "all-icmp", "ssh-tcp"]
  egress_rules        = ["all-all"]
}

################################################################################
# RDS Module
################################################################################

module "rds_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = local.name
  description = "PostgreSQL security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = "${local.name}-db"

  create_db_option_group    = false
  create_db_parameter_group = false

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "11.10"
  family               = "postgres11" # DB parameter group
  major_engine_version = "11"         # DB option group
  instance_class       = "db.t3.micro"

  allocated_storage = 20

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  name                   = "postgres"
  username               = "postgres"
  create_random_password = true
  random_password_length = 12
  port                   = 5432

  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.rds_security_group.this_security_group_id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  backup_retention_period = 0

  tags = local.tags
}

################################################################################
# Outputs
################################################################################
output "ec2_public_ip" { value = module.ec2_instance.public_ip[0] }

output "rds_db_instance_address" { value = module.db.this_db_instance_address }
output "rds_db_instance_endpoint" { value = module.db.this_db_instance_endpoint }
output "rds_db_instance_port" { value = module.db.this_db_instance_port }
output "rds_db_name" { value = module.db.this_db_instance_name }
output "rds_db_username" { value = module.db.this_db_instance_username }
output "rds_db_password" {
  value = module.db.this_db_instance_password
  sensitive = true
}

output "rds_db_url" {
  value = "postgres://${module.db.this_db_instance_username}:${module.db.this_db_instance_password}@${module.db.this_db_instance_endpoint}/${module.db.this_db_instance_name}"
  sensitive = true
}
