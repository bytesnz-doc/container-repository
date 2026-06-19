# Custom Container Registry

A GitHub-hosted container registry providing base images. Images are built, scanned, tested, and published automatically via GitHub Actions and stored in [GitHub Container Registry (GHCR)](https://ghcr.io).

---

## Repository layout

```
.
├── .github/
│   ├── dependabot.yml               # Automated base-image and action update PRs
│   └── workflows/
│       ├── ci.yml                   # Build → Scan → Test → Publish pipeline
│       ├── dependabot-age-check.yml # Reject Dependabot PRs for images < 7 days old
│       └── dependabot-retry.yml     # Daily: re-check ages and unblock PRs automatically
├── dockerfiles/
│   ├── alpine.dockerfile            # Flat image: filename = image name
│   └── developer/
│       └── alpine.dockerfile        # Folder image: folder/filename = image name
├── tests/
│   ├── alpine/
│   │   └── test.sh                  # Tests for the flat alpine image
│   └── developer/
│       ├── test.sh                  # Shared tests for ALL developer/* images
│       └── alpine.sh                # Tests specific to developer/alpine
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

Dockerfiles can live either directly in `dockerfiles/` or in a named subfolder.  
The published image name mirrors the path relative to `dockerfiles/`.

| Dockerfile                                    | Published image                                    |
|-----------------------------------------------|----------------------------------------------------|
| `dockerfiles/alpine.dockerfile`               | `ghcr.io/tepapaatawhai/alpine:latest`              |
| `dockerfiles/developer/alpine.dockerfile`     | `ghcr.io/tepapaatawhai/developer/alpine:latest`    |

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

1. **prepare** — discovers all `*.dockerfile` files (including subfolders) and creates a build matrix filtered to only changed images.
2. **build-scan-test** — for each image in parallel:
   - Builds the image with [Docker Buildx](https://docs.docker.com/buildx/) (layer cache stored in GitHub Actions cache).
   - Scans the image with [Trivy](https://aquasecurity.github.io/trivy/): `CRITICAL`/`HIGH` findings are uploaded to **Security → Code scanning** (SARIF) and fail the job; a PR comment also shows `CRITICAL`/`HIGH`/`MEDIUM` results per image.
   - For flat images, mounts `tests/<image>/` and runs `test.sh`. For folder images, mounts `tests/<folder>/` and runs `test.sh` (shared) then `<image>.sh` (specific). Steps are skipped if the scripts don't exist.
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

Add a file to `dockerfiles/` named `<image-name>.dockerfile`, or create a subfolder for grouped images:

```dockerfile
# dockerfiles/myimage.dockerfile          → ghcr.io/<org>/myimage
# dockerfiles/mygroup/myimage.dockerfile  → ghcr.io/<org>/mygroup/myimage
FROM alpine:3.24.1

RUN apk add --no-cache curl
```

### 2. Create the test scripts

For a **flat image** (`dockerfiles/myimage.dockerfile`), add `tests/myimage/test.sh`:

```sh
#!/bin/sh
set -e

echo "=== myimage tests ==="

if command -v curl >/dev/null 2>&1; then
  echo "  PASS: curl is available"
else
  echo "  FAIL: curl is missing"
  exit 1
fi

echo "All tests passed!"
```

For a **folder image** (`dockerfiles/mygroup/myimage.dockerfile`), you can add two kinds of tests:

- `tests/mygroup/test.sh` — **shared tests** run for every image in the `mygroup` folder (e.g. common invariants like not running as root).
- `tests/mygroup/myimage.sh` — **image-specific tests** run only for `mygroup/myimage`.

Both scripts are optional. The test directory `tests/mygroup/` is mounted read-only at `/tests` inside the container, so scripts can access each other via `/tests/<filename>`.

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
- On pull requests, CI also posts a Trivy comment for each scanned image with `CRITICAL`/`HIGH`/`MEDIUM` counts and top findings.
- `CRITICAL`/`HIGH` results are uploaded to **Security → Code scanning** in this repository.
- Dependabot keeps base images up-to-date, and the age-check workflow ensures only stable (≥ 7-day-old) images are pulled in.
