# GitHub Actions CI/CD portfolio

<!-- cspell:words SARIF -->

Small projects that show CI/CD with GitHub Actions on Azure: a VM deploy over SSH and an Azure Bicep deploy with OIDC.

Each workflow has **path filters**, so it runs only when its own project changes.
Each workflow also **skips its cloud jobs** (with a notice) when the secrets or variables it needs are not set,
so a fork or a fresh clone stays green.

## Projects

| Folder | What it shows | Main tools | Status |
| --- | --- | --- | --- |
| [`project1/`](project1/README.md) | Test a Node.js app, push the image to Docker Hub, deploy it to an Azure VM over SSH | GitHub Actions, Docker, Docker Hub, Azure VM, SSH | Validated locally |
| [`project2/`](project2/README.md) | Validate and deploy a Bicep template with OIDC, what-if before deploy | GitHub Actions, Bicep, Azure CLI, Entra ID federated credentials | Static checks only |

"Validated locally" means the app, image, scans and IaC checks were run on a local machine.
No project was deployed to a real cloud. Each project README has a **Tested** section with the details.

## Workflows

| Workflow | Runs on | Needs |
| --- | --- | --- |
| `ci-cd.yml` | PRs and pushes touching `project1/` | Secrets `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `SERVER_HOST`, `SERVER_USER`, `SSH_PRIVATE_KEY` (deploy only) |
| `deploy-bicep.yml` | PRs and pushes touching `project2/` | Secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`; optional variable `AZURE_RESOURCE_GROUP` |

All actions are pinned to a full commit SHA, with the version in a comment. Dependabot or Renovate can keep them up to date.

## Prerequisites

- Git, Docker and Node.js 20 or newer (for local runs).
- Project 2: Azure CLI with Bicep (`az bicep install`).
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
```

## Repository layout

```text
.
├── .github/workflows/
│   ├── ci-cd.yml                    # project1
│   └── deploy-bicep.yml             # project2
├── project1/                        # Node.js app + Dockerfile, SSH deploy to Azure VM
└── project2/                        # main.bicep (Storage Account)
```

## Skills demonstrated

- GitHub Actions: path filters, job gates, concurrency, timeouts, job summaries.
- Supply-chain hygiene: actions pinned to commit SHAs, least-privilege `permissions`, no long-lived cloud keys.
- OIDC federation to Azure (Entra ID federated credential), so no client secret is stored.
- Containers: multi-stage builds, non-root images, health checks, graceful shutdown, immutable SHA tags.
- Infrastructure as code with Azure Bicep (what-if, lint).
