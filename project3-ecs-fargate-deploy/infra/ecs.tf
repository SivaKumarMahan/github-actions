resource "aws_ecs_cluster" "this" {
  name = local.prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Tofu owns the shape of the task definition (CPU, memory, roles, logs, secrets).
# The pipeline renders the latest revision of this family with a new image and
# registers a new revision, so only the image changes on each deploy.
resource "aws_ecs_task_definition" "app" {
  family                   = local.prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                   = local.container_name
    image                  = "${aws_ecr_repository.app.repository_url}:${var.initial_image_tag}"
    essential              = true
    readonlyRootFilesystem = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    environment = [
      { name = "PORT", value = tostring(var.container_port) },
    ]
    # Read from SSM by the execution role when the task starts.
    secrets = [
      { name = "APP_MESSAGE", valueFrom = aws_ssm_parameter.app_message.arn },
      { name = "API_KEY", valueFrom = aws_ssm_parameter.api_key.arn },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:${var.container_port}/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name                               = local.prefix
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30
  enable_execute_command             = false
  propagate_tags                     = "SERVICE"
  wait_for_steady_state              = false

  # Roll back automatically if new tasks keep failing health checks.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # The pipeline owns the running revision. Without this, every tofu apply
  # would roll the service back to the bootstrap image.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]
}
