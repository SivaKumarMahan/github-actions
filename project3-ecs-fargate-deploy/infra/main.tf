data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  prefix         = "${var.name}-${var.environment}"
  container_name = "app"
  account_id     = data.aws_caller_identity.current.account_id
  partition      = data.aws_partition.current.partition
  https_enabled  = var.certificate_arn != ""
  ssm_prefix     = "/${var.name}/${var.environment}"
}
