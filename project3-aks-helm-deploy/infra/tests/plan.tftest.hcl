# Offline unit tests: `tofu test` plans the stack against mocked azurerm and azuread
# providers. No Azure subscription, tenant or credentials are needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "22222222-2222-2222-2222-222222222222"
    }
  }

  # Attributes that other resources validate need realistic IDs.
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-p3-aks"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-p3-aks/providers/Microsoft.OperationalInsights/workspaces/log-p3-aks"
    }
  }

  mock_resource "azurerm_container_registry" {
    defaults = {
      id           = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-p3-aks/providers/Microsoft.ContainerRegistry/registries/acrp3akstest"
      login_server = "acrp3akstest.azurecr.io"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-p3-aks/providers/Microsoft.ContainerService/managedClusters/aks-p3-aks"
      oidc_issuer_url = "https://eastus2.oic.prod-aks.azure.com/11111111-1111-1111-1111-111111111111/33333333-3333-3333-3333-333333333333/"
    }
  }

  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-p3-aks/providers/Microsoft.Insights/dataCollectionRules/MSCI-p3-aks"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-p3-aks/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mock"
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "66666666-6666-6666-6666-666666666666"
    }
  }

  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "77777777-7777-7777-7777-777777777777"
      app_role_ids = {
        "Application.Read.All" = "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"
      }
    }
  }

  mock_resource "azuread_application" {
    defaults = {
      id        = "/applications/88888888-8888-8888-8888-888888888888"
      client_id = "99999999-9999-9999-9999-999999999999"
    }
  }

  mock_resource "azuread_service_principal" {
    defaults = {
      object_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }
  }
}

variables {
  acr_name          = "acrp3akstest"
  github_repository = "SivaKumarMahan/github-actions"
}

run "cluster_is_hardened" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "OIDC issuer and Workload ID must be on."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "Local admin accounts must be disabled (Entra ID only)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "Kubernetes authorization must use Azure RBAC."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oms_agent[0].msi_auth_for_monitoring_enabled == true
    error_message = "Container Insights must use managed identity auth."
  }

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false
    error_message = "ACR admin user must be off."
  }
}

run "node_pools_autoscale" {
  command = plan

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].min_count == 2
    )
    error_message = "System pool: critical add-ons only, autoscaler on, at least 2 nodes."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster_node_pool.user.mode == "User" &&
      azurerm_kubernetes_cluster_node_pool.user.auto_scaling_enabled &&
      azurerm_kubernetes_cluster_node_pool.user.max_count == 5
    )
    error_message = "User pool must be a User pool with the autoscaler on."
  }
}

run "github_oidc_subjects" {
  command = plan

  assert {
    condition     = azuread_application_federated_identity_credential.github["deploy-staging"].subject == "repo:SivaKumarMahan/github-actions:environment:staging"
    error_message = "Staging deploy must trust only the staging GitHub Environment."
  }

  assert {
    condition     = azuread_application_federated_identity_credential.github["deploy-production"].subject == "repo:SivaKumarMahan/github-actions:environment:production"
    error_message = "Production deploy must trust only the production GitHub Environment."
  }

  assert {
    condition     = azuread_application_federated_identity_credential.github["plan-pull-request"].subject == "repo:SivaKumarMahan/github-actions:pull_request"
    error_message = "Pull requests must map to the plan identity."
  }

  assert {
    condition     = length(azuread_application.github) == 3
    error_message = "Expected three identities: deploy-staging, deploy-production, plan."
  }

  assert {
    condition     = azurerm_federated_identity_credential.app["production"].subject == "system:serviceaccount:production:p3-aks-app"
    error_message = "App Workload ID must trust only the app service account in its namespace."
  }
}

run "least_privilege_roles" {
  command = plan

  assert {
    condition     = toset([for k, v in local.github_role_assignments : k if v.role == "AcrPush"]) == toset(["deploy-staging-acr-push"])
    error_message = "Only the staging deploy identity may push images."
  }

  assert {
    condition     = endswith(azurerm_role_assignment.github["deploy-production-namespace-writer"].scope, "/namespaces/production")
    error_message = "Production deploy must be scoped to the production namespace."
  }

  assert {
    condition     = alltrue([for k, v in local.github_role_assignments : !contains(["Owner", "Contributor", "User Access Administrator"], v.role)])
    error_message = "No GitHub identity may have Owner, Contributor or User Access Administrator."
  }

  assert {
    condition     = toset([for k, v in local.github_role_assignments : v.role if v.app == "plan"]) == toset(["Reader", "Azure Kubernetes Service Cluster User Role"])
    error_message = "The plan identity must stay read-only."
  }

  assert {
    condition     = azurerm_role_assignment.kubelet_acr_pull.role_definition_name == "AcrPull"
    error_message = "The kubelet identity needs AcrPull."
  }

  assert {
    condition     = length(azurerm_role_assignment.plan_state_reader) == 0
    error_message = "No state reader grant without tfstate_storage_account_id."
  }
}

run "state_reader_when_storage_is_set" {
  command = plan

  variables {
    tfstate_storage_account_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/sttfstate"
    grant_plan_graph_read      = false
  }

  assert {
    condition     = azurerm_role_assignment.plan_state_reader[0].role_definition_name == "Storage Blob Data Reader"
    error_message = "The plan identity needs read access to the state blob."
  }

  assert {
    condition     = length(azuread_app_role_assignment.plan_graph_read) == 0
    error_message = "The Graph grant must be optional."
  }
}

run "rejects_bad_acr_name" {
  command = plan

  variables {
    acr_name = "acr-with-dashes"
  }

  expect_failures = [var.acr_name]
}

run "rejects_bad_node_pool_sizes" {
  command = plan

  variables {
    user_node_pool = { min_count = 4, max_count = 2 }
  }

  expect_failures = [var.user_node_pool]
}
