# Copy to backend.hcl (git-ignored) and run: tofu init -backend-config=backend.hcl
# The storage account and container must exist. Your identity needs
# "Storage Blob Data Contributor" on the container (state is read with Entra ID, not keys).
resource_group_name  = "rg-tfstate"
storage_account_name = "sttfstateexample"
container_name       = "tfstate"
key                  = "project3-aks.tfstate"
