# terraform-hasura-demo
Demonstration of hasura graphql engine infrastructure deployment with terraform

# 

```
# step 1
git clone 

# step 2 (install aws cli and run)
# setup ~/.aws/credentials
# choose region: us-east-1
aws configure

# step 3 - Download all dependencies
terraform init

# step 4 - Check execution plan
terraform plan

# step 5 - Create VPC, RDS Cluster, EC2 instance (with Hasura-GraphQL engine running with docker-compose)
terraform apply

# check resutls in AWS Console

# step 6 - Create ALB
mv x_alb.draft x_alb.tf
terraform apply

# check resutls in AWS Console
# open load balancer url/console

# step 7 - create DNS record with SSL certificate for ALB
mv x_route53.draft x_route53.tf
terraform apply

# check resutls in AWS Console
# open load balancer https://hasura.test.sparta.euknyaz.com/console/login
