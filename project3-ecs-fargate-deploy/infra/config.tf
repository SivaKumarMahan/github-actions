# ---------- CloudWatch Logs ----------

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.prefix}"
  retention_in_days = var.log_retention_days
}

# ---------- SSM Parameter Store (app config) ----------

# Plain config: value is managed here.
resource "aws_ssm_parameter" "app_message" {
  name  = "${local.ssm_prefix}/APP_MESSAGE"
  type  = "String"
  value = var.app_message
}

# Secret config: tofu creates a placeholder, the real value is set out of band:
#   aws ssm put-parameter --name /p3-ecs-app/staging/API_KEY --type SecureString \
#     --value '<real value>' --overwrite
# ignore_changes keeps tofu from resetting it, and the real value never lands in git.
resource "aws_ssm_parameter" "api_key" {
  name  = "${local.ssm_prefix}/API_KEY"
  type  = "SecureString"
  value = "change-me"

  lifecycle {
    ignore_changes = [value]
  }
}
