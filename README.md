# Custom Container Registry

A GitHub-hosted container registry providing base images. Images are built, scanned, tested, and published automatically via GitHub Actions and stored in [GitHub Container Registry (GHCR)](https://ghcr.io).

---

## Repository layout

```
.
├── .github/
│   ├── dependabot.yml               # Automated base-image update PRs
│   └── workflows/
│       ├── ci.yml                   # Build → Scan → Test → Publish pipeline
│       ├── dependabot-age-check.yml # Reject Dependabot PRs for images < 7 days old
│       └── dependabot-retry.yml     # Daily: re-check ages and unblock PRs automatically
├── dockerfiles/
│   └── alpine.dockerfile            # One file per image; filename = image name
├── tests/
│   └── alpine/
│       └── test.sh                  # One folder per image containing test script(s)
└── README.md
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Push / PR to main                                          │
│                                                             │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌─────────┐ │
│  │  Build   │──▶│  Scan    │──▶│  Test    │──▶│ Publish │ │
│  │(Buildx)  │   │(Trivy)   │   │(test.sh) │   │(GHCR)   │ │
│  └──────────┘   └──────────┘   └──────────┘   └─────────┘ │
│                                                (main only)  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Dependabot PR                                              │
│                                                             │
│  ┌───────────────────┐   ┌──────────────────────────────┐  │
│  │  Age check        │   │  Main CI pipeline            │  │
│  │  (≥ 7 days old?)  │   │  (Build / Scan / Test)       │  │
│  └───────────────────┘   └──────────────────────────────┘  │
│  Both must pass before the PR can be merged.                │
│                                                             │
│  If the age check fails on day 0:                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Daily retry (04:00 UTC)                             │   │
│  │  Re-checks ages → re-runs failed checks when ready  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Image naming

Each Dockerfile in `dockerfiles/` is named `<image-name>.dockerfile`.  
The published image is `ghcr.io/<org>/<image-name>:<tag>`.

| Dockerfile                       | Published image                          |
|----------------------------------|------------------------------------------|
| `dockerfiles/alpine.dockerfile`  | `ghcr.io/tepapaatawhai/alpine:latest`    |
| `dockerfiles/ubuntu.dockerfile`  | `ghcr.io/tepapaatawhai/ubuntu:latest`    |

### Tags

Every image published from `main` receives two tags:
- `latest` — always points to the most recent build from `main`.
- `<git-sha>` — the short SHA of the commit that triggered the build (immutable, safe to pin).

---

## Build process

### Triggers

| Event                           | Build & Scan & Test | Publish |
|---------------------------------|---------------------|---------|
| PR targeting `main`             | ✓                   | ✗       |
| Push to `main`                  | ✓                   | ✓       |

Changes to files outside `dockerfiles/`, `tests/`, or the workflow files do **not** trigger a rebuild.

### Jobs

1. **prepare** — discovers all `*.dockerfile` files and creates a build matrix.
2. **build-scan-test** — for each image in parallel:
   - Builds the image with [Docker Buildx](https://docs.docker.com/buildx/) (layer cache stored in GitHub Actions cache).
   - Scans the image with [Trivy](https://aquasecurity.github.io/trivy/) for `CRITICAL` and `HIGH` CVEs. Results are uploaded to the **Security → Code scanning** tab as a SARIF report.
   - Mounts `tests/<image>/` into the running container and executes `test.sh`. If no test script exists the step is skipped without error.
3. **publish** — (main branch only, after scan and test pass) builds the image again from the GHA layer cache and pushes it to GHCR.

### Dependabot integration

Dependabot checks `dockerfiles/` weekly (Monday 03:00 NZST) and opens PRs when newer base-image tags are available.

#### Age gate (`dependabot-age-check.yml`)

This workflow runs on every Dependabot PR and verifies that every updated base image was published at least **7 days** ago before the PR can be merged. This protects against pulling in a brand-new image that may not yet have been vetted by the community.

#### Daily retry (`dependabot-retry.yml`)

If the age check fails on day 0 (the image is too new), nothing would normally re-trigger the workflow — the PR would sit blocked indefinitely. The daily retry workflow solves this:

1. Runs every day at **04:00 UTC** (and on demand via `workflow_dispatch`).
2. Finds all open Dependabot PRs that touch `dockerfiles/`.
3. For each PR, fetches the Dockerfile at the PR's head commit and re-checks the base image age via the Docker Hub API.
4. If all images are now ≥ 7 days old → re-runs all failed/cancelled workflow runs on that commit, triggering the age check and the full CI pipeline from scratch.
5. If images are still too new → logs the remaining wait and checks again tomorrow.

No human intervention is required. PRs are unblocked automatically the day the age gate clears.

#### Required status checks

To enforce the age gate, add `Check base image age` as a **required status check** in your branch protection rules:

1. Go to **Settings → Branches → Branch protection rules** for `main`.
2. Enable **Require status checks to pass before merging**.
3. Add `Check base image age` to the required checks list.

---

## How to add a new container image

### 1. Create the Dockerfile

Add a file to `dockerfiles/` named `<image-name>.dockerfile`:

```dockerfile
# dockerfiles/myimage.dockerfile
FROM alpine:3.22

RUN apk add --no-cache curl
```

The filename (without `.dockerfile`) becomes the image name.

### 2. Create the test folder and test script

Add a test script at `tests/<image-name>/test.sh`:

```sh
#!/bin/sh
set -e

echo "=== myimage tests ==="

# Verify curl is installed
if command -v curl >/dev/null 2>&1; then
  echo "PASS: curl is available"
else
  echo "FAIL: curl is missing"
  exit 1
fi

echo "All tests passed!"
```

The test script is executed **inside** the built container. The directory `tests/<image-name>/` is mounted read-only at `/tests` and `/bin/sh /tests/test.sh` is run. Exit with a non-zero code to fail the test.

### 3. Open a pull request

Once your PR is opened the CI pipeline will automatically:
1. Build the new image.
2. Scan it for vulnerabilities.
3. Run your tests.

After the PR is merged to `main` the image is published to GHCR.

---

## Pulling an image

```sh
docker pull ghcr.io/tepapaatawhai/<image-name>:latest
# or pin to a specific commit
docker pull ghcr.io/tepapaatawhai/<image-name>:<git-sha>
```

You may need to authenticate with GHCR first:

```sh
echo "$GITHUB_TOKEN" | docker login ghcr.io -u <your-github-username> --password-stdin
```

---

## Security

- Trivy scans run on every build and block publishing on `CRITICAL` or `HIGH` CVEs.
- Scan results are visible in the **Security → Code scanning** tab of this repository.
- Dependabot keeps base images up-to-date, and the age-check workflow ensures only stable (≥ 7-day-old) images are pulled in.
