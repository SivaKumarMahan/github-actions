# Pre-created identities: the kubelet identity gets AcrPull *before* the first node
# tries to pull, and both identities survive a cluster rebuild (no role re-assignment).
resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = "id-${var.name}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "aks_kubelet" {
  name                = "id-${var.name}-kubelet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# The control plane must be allowed to assign the kubelet identity to the nodes.
resource "azurerm_role_assignment" "aks_kubelet_operator" {
  scope                = azurerm_user_assigned_identity.aks_kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# Nodes pull images from ACR with the kubelet identity. No image pull secrets.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aks_kubelet.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.aks_sku_tier

  # Patch versions and node images are upgraded automatically, inside the
  # maintenance windows below. Minor versions are upgraded on purpose (kubernetes_version).
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Workload ID: pods get Entra tokens through federated credentials, no secrets.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Entra ID only. No local admin kubeconfig, Kubernetes RBAC is managed with Azure RBAC.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  azure_policy_enabled = true

  # Key Vault CSI driver: mount Key Vault secrets as files, with Workload ID. Rotation on.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # Classic node pools with the cluster autoscaler (not Node Auto Provisioning).
  node_provisioning_profile {
    mode = "Manual"
  }

  # System pool: tainted CriticalAddonsOnly, so application pods land on the user pool.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_pool.vm_size
    auto_scaling_enabled         = true
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    only_critical_addons_enabled = true
    zones                        = var.zones
    max_pods                     = 110
    os_sku                       = "AzureLinux"
    # Lets OpenTofu change settings like vm_size by rotating the pool, not recreating the cluster.
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge                     = "33%"
      drain_timeout_in_minutes      = 30
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_control_plane.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.aks_kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.aks_kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.aks_kubelet.id
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }

  auto_scaler_profile {
    balance_similar_node_groups = true
    expander                    = "least-waste"
    scale_down_unneeded         = "10m"
    skip_nodes_with_system_pods = true
  }

  # Container Insights, authenticated with managed identity (see the DCR below).
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
    duration    = 4
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "06:00"
    utc_offset  = "+00:00"
    duration    = 4
  }

  tags = local.tags

  depends_on = [
    azurerm_role_assignment.aks_kubelet_operator,
    azurerm_role_assignment.kubelet_acr_pull,
  ]

  lifecycle {
    # The cluster autoscaler owns the node count.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# User pool for application pods. Separate from the system pool so that app
# load cannot starve CoreDNS and the other add-ons, and so it can scale to its own limits.
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = "User"
  vm_size               = var.user_node_pool.vm_size
  auto_scaling_enabled  = true
  min_count             = var.user_node_pool.min_count
  max_count             = var.user_node_pool.max_count
  zones                 = var.zones
  max_pods              = 110
  os_sku                = "AzureLinux"
  orchestrator_version  = var.kubernetes_version

  node_labels = {
    workload = "apps"
  }

  upgrade_settings {
    max_surge                     = "33%"
    drain_timeout_in_minutes      = 30
    node_soak_duration_in_minutes = 0
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Container Insights data collection rule (managed identity auth needs a DCR).
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
}
