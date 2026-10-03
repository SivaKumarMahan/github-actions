# GitHub Actions -> Azure with OIDC (workload identity federation). No client secrets.
#
# One Entra app + service principal per job role, so each GitHub token can do only
# what that job needs:
#   deploy-staging     environment "staging":    push to ACR, deploy to namespace "staging"
#   deploy-production  environment "production": deploy to namespace "production" (after approval)
#   plan               pull requests and main:   read-only, for "tofu plan" and drift checks
# A token's "sub" claim must match the federated credential exactly.

locals {
  github_oidc_issuer = "https://token.actions.githubusercontent.com"
  token_audience     = "api://AzureADTokenExchange"

  github_apps = merge(
    { for env in var.environments : "deploy-${env}" => "Deploy ${env} from GitHub Actions (environment ${env})" },
    { plan = "Read-only OpenTofu plan from GitHub Actions (pull requests, main)" },
  )

  github_federated_credentials = merge(
    {
      for env in var.environments : "deploy-${env}" => {
        app     = "deploy-${env}"
        subject = "repo:${var.github_repository}:environment:${env}"
      }
    },
    {
      plan-pull-request = {
        app     = "plan"
        subject = "repo:${var.github_repository}:pull_request"
      }
      # Scheduled drift detection and manual runs on main.
      plan-main = {
        app     = "plan"
        subject = "repo:${var.github_repository}:ref:refs/heads/main"
      }
    },
  )

  aks_namespace_scope = { for env in var.environments : env => "${azurerm_kubernetes_cluster.this.id}/namespaces/${env}" }

  # Least privilege, one line per grant.
  github_role_assignments = merge(
    # Build once: only staging pushes the image. Production deploys the same tag.
    contains(var.environments, "staging") ? {
      deploy-staging-acr-push = { app = "deploy-staging", role = "AcrPush", scope = azurerm_container_registry.this.id }
    } : {},
    {
      for env in var.environments : "deploy-${env}-cluster-user" => {
        app   = "deploy-${env}"
        role  = "Azure Kubernetes Service Cluster User Role" # az aks get-credentials only
        scope = azurerm_kubernetes_cluster.this.id
      }
    },
    {
      for env in var.environments : "deploy-${env}-namespace-writer" => {
        app   = "deploy-${env}"
        role  = "Azure Kubernetes Service RBAC Writer" # write access in its own namespace only
        scope = local.aks_namespace_scope[env]
      }
    },
    {
      plan-reader = { app = "plan", role = "Reader", scope = azurerm_resource_group.this.id }
      # The provider reads the cluster's user kubeconfig during refresh. This grants
      # no Kubernetes permissions: the plan identity has no AKS RBAC role.
      plan-cluster-user = { app = "plan", role = "Azure Kubernetes Service Cluster User Role", scope = azurerm_kubernetes_cluster.this.id }
    },
  )
}

resource "azuread_application" "github" {
  for_each = local.github_apps

  display_name = "gh-${var.name}-${each.key}"
  description  = each.value
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "github" {
  for_each = local.github_apps

  client_id = azuread_application.github[each.key].client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "github" {
  for_each = local.github_federated_credentials

  application_id = azuread_application.github[each.value.app].id
  display_name   = "github-${each.key}"
  description    = "GitHub OIDC: ${each.value.subject}"
  issuer         = local.github_oidc_issuer
  audiences      = [local.token_audience]
  subject        = each.value.subject
}

resource "azurerm_role_assignment" "github" {
  for_each = local.github_role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azuread_service_principal.github[each.value.app].object_id
  principal_type       = "ServicePrincipal"
  description          = "GitHub Actions ${each.value.app}"
}

# Read the state blob during a PR plan (plans run with -lock=false, so no write is needed).
resource "azurerm_role_assignment" "plan_state_reader" {
  count = var.tfstate_storage_account_id == null ? 0 : 1

  scope                = var.tfstate_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.github["plan"].object_id
  principal_type       = "ServicePrincipal"
}

# Refreshing the Entra apps in a plan needs directory read access.
data "azuread_service_principal" "msgraph" {
  count     = var.grant_plan_graph_read ? 1 : 0
  client_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
}

resource "azuread_app_role_assignment" "plan_graph_read" {
  count = var.grant_plan_graph_read ? 1 : 0

  app_role_id         = data.azuread_service_principal.msgraph[0].app_role_ids["Application.Read.All"]
  principal_object_id = azuread_service_principal.github["plan"].object_id
  resource_object_id  = data.azuread_service_principal.msgraph[0].object_id
}

# ---------------------------------------------------------------------------
# Workload ID for the app itself: one user-assigned managed identity per
# environment, trusted only for the app's service account in that namespace.
# It has no roles yet. Grant one when the app needs Azure (for example
# "Key Vault Secrets User" on a vault).
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "app" {
  for_each = var.environments

  name                = "id-${var.name}-app-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "app" {
  for_each = var.environments

  name                      = "aks-${each.key}-${var.app_name}"
  user_assigned_identity_id = azurerm_user_assigned_identity.app[each.key].id
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  audience                  = [local.token_audience]
  subject                   = "system:serviceaccount:${each.key}:${var.app_name}"
}
