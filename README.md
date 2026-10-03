# GitHub Actions CI/CD portfolio

<!-- cspell:words aimsplus kubeconform kubelet kubelogin SARIF TFSTATE -->

Three small projects that show CI/CD with GitHub Actions on Azure: a VM deploy over SSH, an Azure Bicep deploy with OIDC,
and an AKS pipeline with Helm, image scanning, OIDC per GitHub Environment and OpenTofu.

Each workflow has **path filters**, so it runs only when its own project changes.
Each workflow also **skips its cloud jobs** (with a notice) when the secrets or variables it needs are not set,
so a fork or a fresh clone stays green.

## Projects

| Folder | What it shows | Main tools | Status |
| --- | --- | --- | --- |
| [`project1/`](project1/README.md) | Test a Node.js app, push the image to Docker Hub, deploy it to an Azure VM over SSH | GitHub Actions, Docker, Docker Hub, Azure VM, SSH | Validated locally |
| [`project2/`](project2/README.md) | Validate and deploy a Bicep template with OIDC, what-if before deploy | GitHub Actions, Bicep, Azure CLI, Entra ID federated credentials | Static checks only |
| [`project3-aks-helm-deploy/`](project3-aks-helm-deploy/README.md) | Build once, Trivy gate + SARIF, push to ACR with OIDC, Helm deploy to AKS (staging, then approved production) with a smoke test and rollback; OpenTofu infra (AKS node pools + autoscaler, Workload ID, Azure RBAC, Container Insights) with `tofu test`, Checkov and a PR plan comment | GitHub Actions, Docker, Trivy, Helm, AKS, ACR, Entra ID, Log Analytics, OpenTofu, Checkov | Validated locally |

"Validated locally" means the app, image, scans and IaC checks were run on a local machine
(for project 3 also a Helm deploy to a local kind cluster). No project was deployed to a real cloud. Each project README has a **Tested** section with the details.

## Workflows

| Workflow | Runs on | Needs |
| --- | --- | --- |
| `ci-cd.yml` | PRs and pushes touching `project1/` | Secrets `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `SERVER_HOST`, `SERVER_USER`, `SSH_PRIVATE_KEY` (deploy only) |
| `deploy-bicep.yml` | PRs and pushes touching `project2/` | Secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`; optional variable `AZURE_RESOURCE_GROUP` |
| `aks-helm-deploy.yml` | PRs and pushes touching `project3-aks-helm-deploy/app/`, `chart/` or `scripts/`, or manual | Variables `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_STAGING`, `AZURE_CLIENT_ID_PRODUCTION`, `ACR_NAME`; Environments `staging`, `production` |
| `tofu-plan-azure.yml` | PRs touching `project3-aks-helm-deploy/infra/`, weekly drift check, or manual | Variables `AZURE_CLIENT_ID_PLAN`, `TFSTATE_STORAGE_ACCOUNT` (plan only; fmt/validate/test and Checkov always run) |

All actions are pinned to a full commit SHA, with the version in a comment. Dependabot or Renovate can keep them up to date.

## Required GitHub settings

Nothing is required for the checks: without these values, every workflow still builds, tests, scans and lints,
and skips only its cloud jobs. To turn the cloud jobs on, add:

| Name | Kind | Project | Notes |
| --- | --- | --- | --- |
| `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` | Secret | 1 | Docker Hub access token, not the password. |
| `SERVER_HOST`, `SERVER_USER`, `SSH_PRIVATE_KEY` | Secret | 1 | SSH deploy target. |
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Secret | 2 | App registration with a federated credential for `main`. |
| `AZURE_RESOURCE_GROUP` | Variable (optional) | 2 | Defaults to `aimsplus`. |
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Variable | 3 | Not secret. Same values as the project 2 secrets. |
| `AZURE_CLIENT_ID_STAGING`, `AZURE_CLIENT_ID_PRODUCTION`, `AZURE_CLIENT_ID_PLAN` | Variable | 3 | From `tofu output github_variables`. OIDC only, no client secrets. |
| `ACR_NAME`, `TFSTATE_STORAGE_ACCOUNT` | Variable | 3 | Optional: `AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_CONTAINER`. |
| `staging`, `production` | Environment | 3 | Add required reviewers to `production`. Optional Environment variable `APP_IDENTITY_CLIENT_ID`. |

Project 3 uses repository **variables**, not secrets, because a job-level `if:` can read variables but not secrets,
and none of these IDs is a secret.

## Prerequisites

- Git, Docker and Node.js 20 or newer (for local runs).
- Project 2: Azure CLI with Bicep (`az bicep install`).
- Project 3: Azure CLI, OpenTofu 1.8+, Helm 3, kubectl and kubelogin; optional kind, kubeconform, Checkov.
- Optional: [actionlint](https://github.com/rhysd/actionlint) to lint the workflows.

## How to use

1. Fork or clone the repository.
2. Pick a project and follow its README. Each one lists the secrets or variables to add under
   **Settings → Secrets and variables → Actions**.
3. Push a change inside that project folder, or start the workflow from the **Actions** tab.

Lint everything locally:

```bash
actionlint
(cd project1 && npm ci && npm test)
az bicep build --file project2/main.bicep
(cd project3-aks-helm-deploy/app && npm ci && npm test)
helm lint project3-aks-helm-deploy/chart --strict -f project3-aks-helm-deploy/chart/values-production.yaml --set image.tag=local
(cd project3-aks-helm-deploy/infra && tofu init -backend=false && tofu validate && tofu test)
```

## Repository layout

```text
.
├── .github/workflows/
│   ├── ci-cd.yml                    # project1
│   ├── deploy-bicep.yml             # project2
│   ├── aks-helm-deploy.yml          # project3: build, scan, deploy staging -> production
│   └── tofu-plan-azure.yml          # project3: infra checks, Checkov, PR plan, drift check
├── project1/                        # Node.js app + Dockerfile, SSH deploy to Azure VM
├── project2/                        # main.bicep (Storage Account)
└── project3-aks-helm-deploy/
    ├── app/                         # Node.js app + Dockerfile
    ├── chart/                       # Helm chart + staging/production values
    ├── scripts/deploy.sh            # helm upgrade --atomic + smoke test
    └── infra/                       # OpenTofu: AKS, ACR, Log Analytics, Entra OIDC identities
```

## Skills demonstrated

- GitHub Actions: path filters, job gates, concurrency, timeouts, GitHub Environments with approvals, artifacts, scheduled jobs, PR comments, job summaries.
- Supply-chain hygiene: actions pinned to commit SHAs, least-privilege `permissions`, no long-lived cloud keys.
- OIDC federation to Azure (Entra ID federated credentials): one identity per job role, bound to the branch, the GitHub Environment or pull requests. No client secrets.
- Containers: multi-stage builds, non-root images, health checks, graceful shutdown, immutable SHA tags.
- Image scanning with Trivy: SARIF to GitHub code scanning plus a HIGH/CRITICAL gate.
- AKS: system and user node pools, cluster autoscaler, auto-upgrade with maintenance windows, Workload ID,
  Entra ID with Azure RBAC scoped to namespaces, ACR pull with the kubelet identity, Container Insights.
- Helm: probes, resources, restricted security context, HPA, PDB, `--atomic` deploys, `helm test` smoke tests.
- Infrastructure as code with OpenTofu (azurerm backend with Entra ID auth, `tofu test` with mocked providers,
  Checkov, plan comments, drift detection) and Azure Bicep (what-if, lint).
