# Three roles, each with only what it needs:
#   execution role - used by the ECS agent: pull the image, write logs, read SSM config
#   task role      - used by the app code at runtime (empty: the app calls no AWS APIs)
#   deploy role    - assumed by GitHub Actions via OIDC: push to ECR, deploy to ECS

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    # Confused-deputy protection: only ECS in this account may assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# ---------- Execution role ----------

resource "aws_iam_role" "execution" {
  name               = "${local.prefix}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }

  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }

  # Only this environment's parameters. SecureString uses the AWS managed
  # aws/ssm key, so no extra kms:Decrypt grant is needed.
  statement {
    sid       = "ReadConfig"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.app_message.arn, aws_ssm_parameter.api_key.arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ---------- Task role ----------

# No policies attached on purpose. Add statements here when the app needs AWS APIs.
resource "aws_iam_role" "task" {
  name               = "${local.prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ---------- GitHub OIDC provider ----------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer uses the thumbprint for GitHub (it trusts the CA), but the
  # API still accepts one. Kept for older tooling.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ---------- GitHub deploy role (one per environment) ----------

# Trust only jobs that run in the matching GitHub Environment of this repo.
# Production jobs need an approval in GitHub before they get a token, so the
# production role cannot be used without that approval.
data "aws_iam_policy_document" "github_deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "${local.prefix}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # Describe/Register task definitions do not support resource-level permissions.
  statement {
    sid       = "TaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "DeployService"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = [aws_ecs_service.app.id]
  }

  # Registering a task definition that names roles requires PassRole on them.
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

# ---------- GitHub plan role (read-only, used by tofu-plan.yml) ----------

# Trusted for pull_request events only. ReadOnlyAccess lets "tofu plan" refresh
# every resource; the extra statement lets it read state from S3. The plan runs
# with -lock=false, so it never writes to the bucket.
data "aws_iam_policy_document" "github_plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  count                = var.create_github_plan_role ? 1 : 0
  name                 = "${var.name}-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.github_plan_assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  count      = var.create_github_plan_role ? 1 : 0
  role       = aws_iam_role.github_plan[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_plan_state" {
  count = var.create_github_plan_role && var.state_bucket_name != "" ? 1 : 0

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}"]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}/project3/*"]
  }

  # Refreshing a SecureString parameter decrypts it. Allow that only through
  # SSM and only for this project's parameters.
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = ["arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/${var.name}/*"]
    }
  }
}

resource "aws_iam_role_policy" "github_plan_state" {
  count  = var.create_github_plan_role && var.state_bucket_name != "" ? 1 : 0
  name   = "read-state"
  role   = aws_iam_role.github_plan[0].id
  policy = data.aws_iam_policy_document.github_plan_state[0].json
}
