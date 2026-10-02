# Example values. Replace the IDs with your own VPC and subnets.
environment       = "production"
aws_region        = "us-east-1"
github_repository = "SivaKumarMahan/github-actions"

vpc_id             = "vpc-0123456789abcdef0"
public_subnet_ids  = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
private_subnet_ids = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2"]

desired_count = 2
app_message   = "Hello from ECS Fargate!"
# certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/..."

# Same AWS account as staging: reuse the OIDC provider created there.
create_github_oidc_provider = false
create_github_plan_role     = false
