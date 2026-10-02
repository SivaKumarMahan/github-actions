# Offline unit tests: `tofu test` plans the stack against a mocked AWS provider.
# No AWS account or credentials are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Validated ARN attributes need realistic values.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/mock"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:111122223333:repository/mock"
      repository_url = "111122223333.dkr.ecr.us-east-1.amazonaws.com/mock"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:111122223333:log-group:/ecs/mock"
    }
  }

  mock_resource "aws_ssm_parameter" {
    defaults = {
      arn = "arn:aws:ssm:us-east-1:111122223333:parameter/mock"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/mock/0123456789abcdef"
      dns_name = "mock-123456789.us-east-1.elb.amazonaws.com"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:111122223333:targetgroup/mock/0123456789abcdef"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:111122223333:cluster/mock"
    }
  }
}

variables {
  environment        = "staging"
  github_repository  = "example-owner/github-actions"
  vpc_id             = "vpc-0123456789abcdef0"
  public_subnet_ids  = ["subnet-a", "subnet-b"]
  private_subnet_ids = ["subnet-c", "subnet-d"]
}

run "http_only_by_default" {
  command = plan

  assert {
    condition     = aws_ecs_service.app.name == "p3-ecs-app-staging"
    error_message = "Service name should be <name>-<environment>."
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "forward"
    error_message = "Without a certificate, HTTP should forward to the target group."
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "No HTTPS listener without a certificate."
  }

  assert {
    condition     = aws_ecr_repository.app.image_tag_mutability == "IMMUTABLE"
    error_message = "ECR tags must be immutable."
  }

  assert {
    condition     = aws_lb.app.enable_deletion_protection == false
    error_message = "Staging ALB should be easy to destroy."
  }

  assert {
    condition     = aws_ssm_parameter.app_message.name == "/p3-ecs-app/staging/APP_MESSAGE"
    error_message = "SSM parameters should be scoped by app and environment."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "Container must run with a read-only root filesystem."
  }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.app.container_definitions)[0].secrets) == 2
    error_message = "APP_MESSAGE and API_KEY should come from SSM."
  }
}

run "https_when_certificate_is_set" {
  command = plan

  variables {
    environment                 = "production"
    certificate_arn             = "arn:aws:acm:us-east-1:111122223333:certificate/example"
    create_github_oidc_provider = true
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect"
    error_message = "With a certificate, HTTP should redirect to HTTPS."
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "HTTPS listener expected when a certificate is set."
  }

  assert {
    condition     = aws_lb.app.enable_deletion_protection == true
    error_message = "Production ALB must have deletion protection."
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "dev"
  }

  expect_failures = [var.environment]
}

run "rejects_single_alb_subnet" {
  command = plan

  variables {
    public_subnet_ids = ["subnet-a"]
  }

  expect_failures = [var.public_subnet_ids]
}
