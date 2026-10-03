# Example values. Copy to terraform.tfvars (git-ignored) and change them.
acr_name = "acrp3aksexample" # must be globally unique

# Entra ID group(s) that get cluster admin, to create namespaces and debug.
admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]

# Lets the PR plan identity read the state blob.
tfstate_storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/sttfstateexample"

# Cheaper lab settings. Remove for production-like defaults.
# aks_sku_tier     = "Free"
# system_node_pool = { min_count = 1 }
