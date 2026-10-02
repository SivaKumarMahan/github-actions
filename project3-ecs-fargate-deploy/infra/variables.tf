variable "aws_region" {
  description = "AWS region for every resource."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Short application name. Used as a prefix for resource names."
  type        = string
  default     = "p3-ecs-app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.name))
    error_message = "name must be 2-21 lowercase letters, numbers or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Must match the GitHub Environment name."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, as owner/repo."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/repo."
  }
}

# ---------- Networking (the VPC is owned outside this stack) ----------

variable "vpc_id" {
  description = "Existing VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least two Availability Zones."
  }
}

variable "private_subnet_ids" {
  description = "Subnets for the Fargate tasks. Private subnets need a NAT gateway or VPC endpoints for ECR, logs and SSM."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Give tasks a public IP. Only needed when tasks run in public subnets without NAT (for example a sandbox default VPC)."
  type        = bool
  default     = false
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, the ALB serves HTTPS on 443 and redirects HTTP to HTTPS."
  type        = string
  default     = ""
}

# ---------- Service sizing ----------

variable "container_port" {
  description = "Port the app listens on inside the container."
  type        = number
  default     = 3000
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of running tasks."
  type        = number
  default     = 2
}

variable "initial_image_tag" {
  description = "Image tag used by the first task definition revision. The pipeline replaces it on every deploy."
  type        = string
  default     = "bootstrap"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 30
}

variable "app_message" {
  description = "Non-secret config stored in SSM Parameter Store and injected as APP_MESSAGE."
  type        = string
  default     = "Hello from ECS Fargate!"
}

# ---------- GitHub OIDC ----------

variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. Set false if it already exists (for example, created by the other environment in the same account)."
  type        = bool
  default     = true
}

variable "create_github_plan_role" {
  description = "Create the read-only role used by tofu-plan.yml on pull requests. Create it once per account."
  type        = bool
  default     = false
}

variable "state_bucket_name" {
  description = "S3 bucket that holds the OpenTofu state. The plan role gets read access to it."
  type        = string
  default     = ""
}

variable "ecr_force_delete" {
  description = "Allow tofu destroy to delete the ECR repository even when it still has images."
  type        = bool
  default     = false
}
