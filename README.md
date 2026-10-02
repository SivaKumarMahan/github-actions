# GitHub Actions CI/CD portfolio

<!-- cspell:words SARIF -->

Three small projects that show CI/CD with GitHub Actions: a VM deploy over SSH, an Azure Bicep deploy with OIDC,
and an AWS ECS Fargate pipeline with image scanning, OIDC, GitHub Environments and OpenTofu.

Each workflow has **path filters**, so it runs only when its own project changes.
Each workflow also **skips its cloud jobs** (with a notice) when the secrets or variables it needs are not set,
so a fork or a fresh clone stays green.

## Projects

| Folder | What it shows | Main tools | Status |
| --- | --- | --- | --- |
| [`project1/`](project1/README.md) | Test a Node.js app, push the image to Docker Hub, deploy it to an Azure VM over SSH | GitHub Actions, Docker, Docker Hub, Azure VM, SSH | Validated locally |
| [`project2/`](project2/README.md) | Validate and deploy a Bicep template with OIDC, what-if before deploy | GitHub Actions, Bicep, Azure CLI, Entra ID federated credentials | Static checks only |
| [`project3-ecs-fargate-deploy/`](project3-ecs-fargate-deploy/README.md) | Build once, Trivy gate + SARIF, push to ECR with OIDC, deploy to ECS Fargate behind an ALB, staging then approved production; OpenTofu infra with a PR plan comment | GitHub Actions, Docker, Trivy, AWS ECR/ECS/ALB/IAM/SSM/CloudWatch, OpenTofu | Validated locally |

"Validated locally" means the app, image, scans and IaC checks were run on a local machine.
No project was deployed to a real cloud. Each project README has a **Tested** section with the details.

## Workflows

| Workflow | Runs on | Needs |
| --- | --- | --- |
| `ci-cd.yml` | PRs and pushes touching `project1/` | Secrets `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `SERVER_HOST`, `SERVER_USER`, `SSH_PRIVATE_KEY` (deploy only) |
| `deploy-bicep.yml` | PRs and pushes touching `project2/` | Secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`; optional variable `AZURE_RESOURCE_GROUP` |
| `ecs-fargate-deploy.yml` (+ reusable `ecs-fargate-deploy-env.yml`) | PRs and pushes touching `project3-ecs-fargate-deploy/app/`, or manual | Variables `AWS_DEPLOY_ROLE_ARN_STAGING`, `AWS_DEPLOY_ROLE_ARN_PRODUCTION`; Environments `staging`, `production` |
| `tofu-plan.yml` | PRs touching `project3-ecs-fargate-deploy/infra/` | Variables `AWS_PLAN_ROLE_ARN`, `TF_STATE_BUCKET` (plan only; fmt/validate/test always run) |

All actions are pinned to a full commit SHA, with the version in a comment. Dependabot or Renovate can keep them up to date.

## Prerequisites

- Git, Docker and Node.js 20 or newer (for local runs).
- Project 2: Azure CLI with Bicep (`az bicep install`).
- Project 3: OpenTofu 1.8+ and AWS CLI v2.
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
(cd project3-ecs-fargate-deploy/infra && tofu init -backend=false && tofu validate && tofu test)
```

## Repository layout

```text
.
├── .github/workflows/
│   ├── ci-cd.yml                    # project1
│   ├── deploy-bicep.yml             # project2
│   ├── ecs-fargate-deploy.yml       # project3: build, scan, promote
│   ├── ecs-fargate-deploy-env.yml   # project3: reusable deploy to one environment
│   └── tofu-plan.yml                # project3: infra PR checks and plan comment
├── project1/                        # Node.js app + Dockerfile, SSH deploy to Azure VM
├── project2/                        # main.bicep (Storage Account)
└── project3-ecs-fargate-deploy/
    ├── app/                         # Node.js app + Dockerfile
    └── infra/                       # OpenTofu: ECR, ECS, ALB, IAM, SSM, CloudWatch
```

## Skills demonstrated

- GitHub Actions: path filters, job gates, concurrency, timeouts, reusable workflows, GitHub Environments with approvals, job summaries.
- Supply-chain hygiene: actions pinned to commit SHAs, least-privilege `permissions`, no long-lived cloud keys.
- OIDC federation to Azure (Entra ID federated credential) and to AWS (IAM role per environment, trust bound to the Environment).
- Containers: multi-stage builds, non-root images, health checks, graceful shutdown, immutable SHA tags.
- Image scanning with Trivy: SARIF to GitHub code scanning plus a HIGH/CRITICAL gate.
- AWS ECS Fargate rolling deploys behind an ALB, circuit breaker with rollback, config from SSM Parameter Store.
- Infrastructure as code with OpenTofu (S3 backend with native locking, `tofu test` with mocked providers) and Azure Bicep (what-if, lint).
