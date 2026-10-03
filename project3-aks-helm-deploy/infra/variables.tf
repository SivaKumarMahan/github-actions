variable "name" {
  description = "Short name used in every resource name (for example rg-<name>, aks-<name>)."
  type        = string
  default     = "p3-aks"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.name))
    error_message = "name must be 3-20 characters: lowercase letters, numbers and hyphens."
  }
}

variable "location" {
  description = "Azure region. It must support availability zones if zones is not empty."
  type        = string
  default     = "eastus2"
}

variable "acr_name" {
  description = "Azure Container Registry name. Globally unique, 5-50 letters and numbers."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 letters and numbers only."
  }
}

variable "acr_sku" {
  description = "ACR SKU. Premium adds private endpoints, geo-replication and retention policies."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard or Premium."
  }
}

variable "github_repository" {
  description = "GitHub repository (owner/name) that may log in with OIDC."
  type        = string
  default     = "SivaKumarMahan/github-actions"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "environments" {
  description = "Application environments. Each one is a Kubernetes namespace and a GitHub Environment."
  type        = set(string)
  default     = ["staging", "production"]

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[a-z][a-z0-9-]{1,30}$", e))])
    error_message = "Environment names must be lowercase DNS labels."
  }
}

variable "app_name" {
  description = "Helm release / Kubernetes service account name of the app (used by Workload ID)."
  type        = string
  default     = "p3-aks-app"
}

variable "kubernetes_version" {
  description = "AKS version, for example \"1.33\". null = the current AKS default. Patches are applied automatically."
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "Free (no SLA, labs) or Standard (uptime SLA, production)."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be Free, Standard or Premium."
  }
}

variable "zones" {
  description = "Availability zones for both node pools. Use [] in regions without zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "system_node_pool" {
  description = "System node pool: runs only critical add-ons (CoreDNS, metrics-server, ...)."
  type = object({
    vm_size   = optional(string, "Standard_D2s_v5")
    min_count = optional(number, 2)
    max_count = optional(number, 3)
  })
  default = {}

  validation {
    condition     = var.system_node_pool.min_count >= 1 && var.system_node_pool.min_count <= var.system_node_pool.max_count
    error_message = "system_node_pool: need 1 <= min_count <= max_count."
  }
}

variable "user_node_pool" {
  description = "User node pool: runs the application pods. The cluster autoscaler scales it."
  type = object({
    vm_size   = optional(string, "Standard_D2s_v5")
    min_count = optional(number, 1)
    max_count = optional(number, 5)
  })
  default = {}

  validation {
    condition     = var.user_node_pool.min_count >= 0 && var.user_node_pool.min_count <= var.user_node_pool.max_count
    error_message = "user_node_pool: need 0 <= min_count <= max_count."
  }
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that get cluster admin (to create namespaces, debug). Keep this small."
  type        = list(string)
  default     = []
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server. Empty = public. GitHub-hosted runners have changing IPs."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "tfstate_storage_account_id" {
  description = "Resource ID of the state storage account. If set, the plan identity gets Storage Blob Data Reader on it."
  type        = string
  default     = null
}

variable "grant_plan_graph_read" {
  description = "Give the plan identity Microsoft Graph Application.Read.All, so it can refresh the Entra objects in a plan. Needs a Privileged Role Administrator to apply."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}
