# Example values. Replace the IDs with your own VPC and subnets.
environment       = "staging"
aws_region        = "us-east-1"
github_repository = "SivaKumarMahan/github-actions"

vpc_id             = "vpc-0123456789abcdef0"
public_subnet_ids  = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
private_subnet_ids = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2"]

desired_count = 1
app_message   = "Hello from ECS Fargate (staging)!"

# Account-wide resources are created once, by the staging stack.
create_github_oidc_provider = true
create_github_plan_role     = true
state_bucket_name           = "TODO-tofu-state-bucket"
ecr_force_delete            = true
