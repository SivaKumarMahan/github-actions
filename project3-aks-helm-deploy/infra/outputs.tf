output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "app_identity_client_ids" {
  description = "Per environment: set as the APP_IDENTITY_CLIENT_ID Environment variable to turn on Workload ID."
  value       = { for env, id in azurerm_user_assigned_identity.app : env => id.client_id }
}

# Repository variables for the workflows. None of them is a secret.
# Example: tofu output -json github_variables | jq -r 'to_entries[] | "\(.key) \(.value)"' |
#          while read -r k v; do gh variable set "$k" --body "$v"; done
output "github_variables" {
  description = "Values for Settings > Secrets and variables > Actions > Variables."
  value = merge(
    {
      AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
      AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
      AZURE_CLIENT_ID_PLAN  = azuread_application.github["plan"].client_id
      AKS_RESOURCE_GROUP    = azurerm_resource_group.this.name
      AKS_CLUSTER_NAME      = azurerm_kubernetes_cluster.this.name
      ACR_NAME              = azurerm_container_registry.this.name
    },
    { for env in var.environments : "AZURE_CLIENT_ID_${upper(env)}" => azuread_application.github["deploy-${env}"].client_id },
  )
}
