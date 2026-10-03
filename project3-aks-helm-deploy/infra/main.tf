data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

locals {
  tags = merge(
    {
      project    = var.name
      managed-by = "opentofu"
      repository = var.github_repository
    },
    var.tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

# Log Analytics for Container Insights (logs, metrics, KQL alerts).
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  # Agents authenticate with managed identity; no shared workspace keys.
  local_authentication_enabled = false
  tags                         = local.tags
}

resource "azurerm_container_registry" "this" {
  name                = var.acr_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.acr_sku
  # No shared admin user: pushes use Entra ID (OIDC), pulls use the kubelet identity.
  admin_enabled          = false
  anonymous_pull_enabled = false
  # Public endpoint is needed for GitHub-hosted runners. See README for the private option.
  public_network_access_enabled = true
  tags                          = local.tags
}
