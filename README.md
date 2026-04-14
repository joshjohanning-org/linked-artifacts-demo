# 🔗 Linked Artifacts Demo

> A comprehensive demo of GitHub's [Linked Artifacts](https://docs.github.com/en/enterprise-cloud@latest/code-security/concepts/supply-chain-security/linked-artifacts) feature — showing how to track what's deployed in each environment and enforce promotion ordering.

## What is Linked Artifacts?

**Linked Artifacts** is a GitHub Enterprise Cloud feature that provides an org-wide view of software artifacts built with GitHub Actions. It tracks:

- **Storage records** — what was built, where it's stored, and its provenance attestation
- **Deployment records** — which environments an artifact is deployed to and its runtime risks

Find it at: **Organization → Packages tab → Linked artifacts** (left sidebar)

### Linked Artifacts vs. Deployments Dashboard

| | Deployments Dashboard | Linked Artifacts |
|---|---|---|
| **Scope** | Per-repo | Org-wide |
| **Tracks** | Commits/refs | Artifacts (with cryptographic digest) |
| **Security** | No integration | Feeds into code scanning & Dependabot alert prioritization |
| **Provenance** | None | Signed SLSA attestations |
| **Runtime risks** | No | Yes (internet-exposed, sensitive data) |

## What This Demo Does

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│          │    │          │    │          │    │          │    │          │
│  Build   │───▶│   Dev    │───▶│   QA     │───▶│ Staging  │───▶│   Prod   │
│          │    │          │    │          │    │          │    │          │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
     │               │               │               │               │
     │               │               │               │               │
     ▼               ▼               ▼               ▼               ▼
  Push to         Register        Verify Dev      Verify QA      Verify Staging
  GHCR +          deployment      deployment      deployment     deployment
  Attest          record          record exists   record exists  record exists
  (auto-creates   (Dev)           → Register QA   → Register     → Register
  storage                                         Staging        Production
  record)
```

### Two Workflows

#### 1. `build-and-deploy.yml` — Happy Path
Triggered on push to `main`. Builds a Docker image, pushes to GHCR, attests provenance, then deploys sequentially through all 4 environments. Each promotion step:
- **Verifies** the artifact was deployed to the prior environment (via Linked Artifacts API)
- **Registers** a deployment record after successful deployment

#### 2. `hotfix-skip-env.yml` — Negative Test ❌
Manually triggered. Builds a **new** image and tries to deploy it directly to a higher environment (e.g., Staging), skipping the lower ones. The verification gate **blocks** this because no prior deployment records exist for the new image's digest.

This proves the enforcement isn't just `needs:` job ordering — it's the real API check.

## How It Works

### 1. Build & Attest

The build job pushes a Docker image to GHCR and generates a [signed provenance attestation](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations) using `actions/attest`. With `push-to-registry: true` and `artifact-metadata: write` permission, this **automatically creates a storage record** on the linked artifacts page.

### 2. Deployment Records

After each deployment, the workflow calls the artifact metadata REST API:

```bash
gh api -X POST \
  "orgs/{org}/artifacts/metadata/deployment-record" \
  -f name="linked-artifacts-demo" \
  -f digest="sha256:abc..." \
  -f status="deployed" \
  -f logical_environment="production" \
  -f deployment_name="prod-deploy-42" \
  -f github_repository="org/repo"
```

### 3. Verification Gate

Before each promotion, the [`verify-deployment.sh`](.github/scripts/verify-deployment.sh) script queries the API:

```bash
GET /orgs/{org}/artifacts/{digest}/metadata/deployment-records
```

It checks if a deployment record exists for the required prior environment. If not, the job fails and promotion is blocked.

### Environment Mapping

| GitHub Environment | `logical_environment` | Requires Prior |
|---|---|---|
| Dev | `development` | — (first) |
| QA | `testing` | `development` |
| Staging | `staging` | `testing` |
| Production | `production` | `staging` |

## Setup

### Prerequisites

- GitHub Enterprise Cloud organization
- Repository in the organization with Actions enabled
- `artifact-metadata: write` permission available (GHEC feature)

### 1. Create GitHub Environments

Create the 4 environments for the repository. You can do this in **Settings → Environments** or via the API:

```bash
# Create all 4 environments
for env in Dev QA Staging Production; do
  gh api -X PUT \
    "repos/{owner}/{repo}/environments/${env}" \
    --silent
done

# Optionally add a wait timer to Production
gh api -X PUT \
  "repos/{owner}/{repo}/environments/Production" \
  -f "wait_timer=1" \
  --silent
```

### 2. Push Code & Trigger

```bash
git add -A
git commit -m "Add linked artifacts demo"
git push origin main
```

The `build-and-deploy.yml` workflow will trigger automatically.

### 3. View Results

After the pipeline completes:

1. Go to your **Organization page**
2. Click the **Packages** tab
3. Click **Linked artifacts** in the left sidebar
4. Find `linked-artifacts-demo` — you'll see:
   - Storage record with provenance attestation
   - Deployment records for Dev, QA, Staging, and Production

### 4. Test the Negative Case

1. Go to **Actions → "Hotfix: Skip Environment (Demo)"**
2. Click **Run workflow**
3. Select **Staging** or **Production** as the target
4. Watch the verification gate **fail** because the new image was never deployed to the lower environments

## Repository Structure

```
├── .github/
│   ├── scripts/
│   │   └── verify-deployment.sh       # Reusable verification gate
│   └── workflows/
│       ├── build-and-deploy.yml       # Main CI/CD pipeline (happy path)
│       └── hotfix-skip-env.yml        # Negative test (skip environments)
├── src/
│   └── index.js                       # Simple Express.js app
├── Dockerfile                         # Multi-stage Docker build
├── package.json
└── README.md
```

## Key API Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `orgs/{org}/artifacts/metadata/storage-record` | POST | Register where an artifact is stored |
| `orgs/{org}/artifacts/metadata/deployment-record` | POST | Register a deployment to an environment |
| `orgs/{org}/artifacts/{digest}/metadata/deployment-records` | GET | List deployment records for an artifact |
| `orgs/{org}/artifacts/{digest}/metadata/storage-records` | GET | List storage records for an artifact |

## Links

- [About Linked Artifacts](https://docs.github.com/en/enterprise-cloud@latest/code-security/concepts/supply-chain-security/linked-artifacts)
- [Uploading storage and deployment data](https://docs.github.com/en/enterprise-cloud@latest/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/upload-linked-artifacts)
- [Viewing the linked artifacts page](https://docs.github.com/en/enterprise-cloud@latest/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/view-linked-artifacts)
- [Artifact Metadata REST API](https://docs.github.com/en/enterprise-cloud@latest/rest/orgs/artifact-metadata)
- [Artifact Attestations](https://docs.github.com/en/enterprise-cloud@latest/actions/concepts/security/artifact-attestations)