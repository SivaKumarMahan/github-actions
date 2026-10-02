output "alb_url" {
  description = "Public URL of the service."
  value       = "${local.https_enabled ? "https" : "http"}://${aws_lb.app.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository the pipeline pushes to."
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "task_definition_family" {
  value = aws_ecs_task_definition.app.family
}

output "container_name" {
  value = local.container_name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "github_deploy_role_arn" {
  description = "Set this as the repository variable AWS_DEPLOY_ROLE_ARN_<ENVIRONMENT>."
  value       = aws_iam_role.github_deploy.arn
}

output "github_plan_role_arn" {
  description = "Set this as the repository variable AWS_PLAN_ROLE_ARN."
  value       = var.create_github_plan_role ? aws_iam_role.github_plan[0].arn : null
}

output "github_environment_variables" {
  description = "Values to copy into the GitHub Environment of the same name."
  value = {
    ECR_REPOSITORY         = aws_ecr_repository.app.name
    ECS_CLUSTER            = aws_ecs_cluster.this.name
    ECS_SERVICE            = aws_ecs_service.app.name
    TASK_DEFINITION_FAMILY = aws_ecs_task_definition.app.family
    CONTAINER_NAME         = local.container_name
    APP_URL                = "${local.https_enabled ? "https" : "http"}://${aws_lb.app.dns_name}"
  }
}
