terraform {
  required_version = ">= 1.8.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
  }

  # Partial backend configuration: the storage account is created once, outside
  # this stack. Pass the rest at init time (see backend.example.hcl):
  #   tofu init -backend-config=backend.hcl
  # use_azuread_auth: state is read with Entra ID (RBAC), not storage account keys.
  backend "azurerm" {
    use_azuread_auth = true
  }
}

# Credentials come from the environment: "az login" locally, or ARM_USE_OIDC=true
# with ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID in GitHub Actions.
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  # Do not register resource providers on every run. That needs subscription-wide
  # rights, which the read-only plan identity does not have. Register the providers
  # listed in the README once instead.
  resource_provider_registrations = "none"
}

provider "azuread" {}
