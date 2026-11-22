# Release Workflows

Call reusable workflows at `jobs.<job>.uses`. Their inputs are typed values, so
booleans are written as `true` or `false` without quotes.

## Comprehensive release gateway

File: `.github/workflows/w-v2-release.yaml`

This is the broad release entry point. Each enabled project flag creates an
independent job; enabling several flags runs several release jobs. If all four
project or Docker flags are false, the workflow runs `publish-basic`.

| Input | Type | Default | Meaning |
|---|---|---|---|
| `default-branch` | string | `trunk` | Ref checked out by each job |
| `run-on` | string | `ubuntu-latest` | Runner label |
| `python-project` | boolean | `false` | Run `publish-python` |
| `nodejs-project` | boolean | `false` | Run `publish-npm` |
| `latex-project` | boolean | `false` | Run `publish-latex` |
| `docker-push` | boolean | `false` | Run `docker-push` |
| `git-token-path` | string | Stone Home GitHub PAT path | GitHub release or push credential URI |
| `nodejs-version` | string | `26` | Node.js version for Node and LaTeX jobs |
| `python-version` | string | `3.11` | Python version |
| `poetry-version` | string | `1.8.5` | Poetry version |
| `version-id` | string | empty | Python version branch and package version |
| `pypi-enable` | boolean | `false` | Publish Python package to PyPI |
| `pypi-token-path` | string | Stone Home PyPI token path | PyPI credential URI |
| `kubernetes-mode` | boolean | `false` | Select ARC paths inside composite actions |
| `docker-registry` | string | `ghcr` | `ghcr` or `dockerhub` |
| `docker-hub-username` | string | empty | Forwarded as the registry username for either registry; optional for GHCR with the job token |
| `docker-hub-password-path` | string | empty | Forwarded as the registry token URI for either registry. Empty means: GHCR uses the job's `github.token`, Docker Hub uses the Stone Home Docker PAT path |
| `docker-image-name` | string | empty | Image reference without tag |
| `dockerfile` | string | `Dockerfile` | Dockerfile path |
| `docker-context` | string | `.` | Docker build context |
| `docker-tags` | string | `latest` | Comma-separated tag suffixes |

| Secret | Required | Meaning |
|---|---:|---|
| `onepass-token` | Yes | 1Password service-account token |

The workflow is read-only by default and each job asks only for what it uses:
`contents: write` for the release jobs, plus `id-token: write` for the npm job
and `packages: write` for the Docker job. The caller must allow at least those.
Releases and issue or pull-request comments go through the 1Password token, so
the job token needs no `issues` or `pull-requests` permission.

### Basic release

With every project flag left false, the workflow invokes `publish-basic`:

```yaml
jobs:
  release:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/w-v2-release.yaml@trunk
    secrets:
      onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

### Python release

Always supply `version-id`. The action creates `versions/<version-id>` even when
PyPI publication is disabled.

```yaml
jobs:
  release:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/w-v2-release.yaml@trunk
    with:
      python-project: true
      version-id: v1.4.0
      pypi-enable: true
      python-version: "3.12"
      poetry-version: "2.1.4"
    secrets:
      onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

### Node.js release

```yaml
jobs:
  release:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/w-v2-release.yaml@trunk
    with:
      nodejs-project: true
      nodejs-version: "26"
    secrets:
      onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The called action uses npm trusted publishing by default. Configure the package
registry and grant `id-token: write` in the caller.

### LaTeX release

```yaml
jobs:
  release:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/w-v2-release.yaml@trunk
    with:
      latex-project: true
      nodejs-version: "26"
    secrets:
      onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The workflow does not accept the main or appendix filename. Put those flags in
the consumer's semantic-release `prepareCmd`; see
[LaTeX release](latex-release.md).

### Docker release

```yaml
jobs:
  release:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/w-v2-release.yaml@trunk
    with:
      docker-push: true
      docker-registry: ghcr
      docker-image-name: ghcr.io/stone-home/example
      docker-tags: latest,1.4.0
    secrets:
      onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

Despite their names, `docker-hub-username` and
`docker-hub-password-path` are forwarded for both registries. With the path left
empty, GHCR pushes use the job's own `github.token` and Docker Hub pushes use
the Stone Home Docker PAT path; Docker Hub still needs the username. In
Kubernetes mode the selected runner must already expose `/kaniko/executor`; the
workflow does not add a Kaniko container.

## `release.yaml`

This earlier reusable workflow runs one semantic-release job and optionally
prepares Node or LaTeX dependencies before release.

| Input | Type | Default | Meaning |
|---|---|---|---|
| `nodejs_project` | boolean | `false` | Run `npm ci` and `npm run build` |
| `latex_project` | boolean | `false` | Install TeX Live |
| `git_token_path` | string | Stone Home GitHub PAT path | Semantic-release credential URI |

| Secret | Required |
|---|---:|
| `onepass_token` | Yes |

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  release:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/release.yaml@trunk
    with:
      nodejs_project: true
    secrets:
      onepass_token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

Unlike the comprehensive gateway, this workflow invokes
`npx semantic-release@25.0.2` directly and uses underscore input names. Keep it
for callers that need this single-job flow; new multi-target integrations can
use `w-v2-release.yaml`.

## `poetry-publish.yaml`

This standalone workflow creates a version branch, updates
`pyproject.toml`, builds, and always publishes to PyPI.

| Input | Type | Required/default | Meaning |
|---|---|---|---|
| `python-version` | string | default `3.11` | Python version |
| `poetry-version` | string | default `1.8.5` | Poetry version |
| `version-id` | string | required | Version and `versions/<id>` branch suffix |

| Secret | Required |
|---|---:|
| `onepass_token` | Yes |

```yaml
permissions:
  contents: write

jobs:
  publish:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/poetry-publish.yaml@trunk
    with:
      python-version: "3.12"
      poetry-version: "2.1.4"
      version-id: v1.4.0
    secrets:
      onepass_token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The workflow uses fixed 1Password paths for its GitHub and PyPI tokens and has
no build-only switch. Use the comprehensive gateway when token paths or optional
PyPI publication need to be configured.
