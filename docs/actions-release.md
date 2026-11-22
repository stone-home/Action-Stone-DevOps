# Release and Publishing Actions

These actions make externally visible changes. Use protected environments and
repository-specific release rules where appropriate. Examples use `@trunk`; see
[Getting started](getting-started.md) before choosing a ref or permissions.

## `publish-basic`

Runs semantic-release for a generic repository such as a shell-script or
configuration project. It sets up Node.js without `npm ci`, loads a GitHub token
from 1Password, installs the repository's pinned semantic-release toolchain by
default, and runs `npx semantic-release`.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `node-version` | No | `26` | Node.js version |
| `onepass-token` | Yes | — | 1Password service-account token |
| `github-token-path` | No | Stone Home GitHub PAT path | Release token URI |
| `kubernetes-mode` | No | `false` | Use the ARC 1Password path |
| `use-unified-semantic-version` | No | `true` | Deprecated and ignored; the pinned toolchain is always installed |

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: stone-home/Action-Stone-DevOps/.github/actions/publish-basic@trunk
        with:
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The caller supplies `.releaserc` or another semantic-release configuration. The
pinned toolchain is always installed first and the release runs with
`npx --no-install`, so a missing install fails the step instead of downloading
the latest semantic-release.

## `publish-npm`

Runs `npm ci`, `npm run build`, and semantic-release for a Node package. Trusted
publishing is enabled by default; token-based publishing reads an npm token from
1Password.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `node-version` | No | `26` | Node.js version |
| `enable-trusted-publisher` | No | `true` | Use registry trusted publishing instead of an npm token |
| `npm-token-path` | No | Stone Home npm token path | Used when trusted publishing is false |
| `github-token-path` | No | Stone Home GitHub PAT path | Semantic-release GitHub token URI |
| `onepass-token` | Yes | — | 1Password service-account token |
| `kubernetes-mode` | No | `false` | Use ARC secret loading |
| `use-unified-semantic-version` | No | `true` | Deprecated and ignored; the pinned toolchain is always installed |

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write
  id-token: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: stone-home/Action-Stone-DevOps/.github/actions/publish-npm@trunk
        with:
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
          enable-trusted-publisher: "true"
```

The caller needs `package-lock.json`, a `build` script, package metadata, a
semantic-release configuration, and registry-side trusted-publisher setup. For
token publication, pass `enable-trusted-publisher: "false"` and optionally
replace `npm-token-path`.

## `publish-python`

Creates and pushes `versions/<version-id>`, removes a leading `v` from the
version written to `pyproject.toml`, commits that change, builds with Poetry,
and optionally publishes to PyPI. This action does not run semantic-release.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `python-version` | No | `3.11` | Python version |
| `poetry-version` | No | `1.8.5` | Poetry version |
| `version-id` | Yes | — | Branch suffix and Poetry version, normally `vX.Y.Z` |
| `github-token-path` | No | Stone Home GitHub PAT path | Git credential URI |
| `pypi-enable` | No | `false` | Publish the built package |
| `pypi-token-path` | No | Stone Home PyPI token path | Token used when publication is enabled |
| `onepass-token` | Yes | — | 1Password service-account token |
| `kubernetes-mode` | No | `false` | Use ARC setup and secret loading |

```yaml
permissions:
  contents: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: stone-home/Action-Stone-DevOps/.github/actions/publish-python@trunk
        with:
          version-id: v1.4.0
          pypi-enable: "true"
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The branch and version commit happen even when `pypi-enable` is false. Ensure
the version branch does not already exist and that the checkout credential can
push it.

## `publish-latex`

Installs Node dependencies, caches and installs TeX Live, configures 1Password,
checks this repository out to `.devops`, and runs the consumer's
semantic-release configuration.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `node-version` | No | `26` | Node.js version |
| `github-token-path` | No | Stone Home GitHub PAT path | Semantic-release GitHub token URI |
| `onepass-token` | Yes | — | 1Password service-account token |
| `kubernetes-mode` | No | `false` | Use ARC secret loading |
| `use-unified-semantic-version` | No | `true` | Deprecated and ignored; the pinned toolchain is always installed |

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: stone-home/Action-Stone-DevOps/.github/actions/publish-latex@trunk
        with:
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The consumer needs `package-lock.json` and a `.releaserc.js` whose prepare step
calls `.devops/scripts/latex/prepare-release.sh`. Main-document, appendix, diff,
and asset configuration is covered in [LaTeX release](latex-release.md).

## `docker-push`

Builds and pushes one image to GHCR or Docker Hub. Normal runners use Docker
Buildx; Kubernetes mode calls Kaniko without a Docker socket.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `registry` | No | `ghcr` | `ghcr` or `dockerhub` |
| `registry-username` | For Docker Hub, or GHCR with a 1Password token | empty | Login username; with the GHCR job token it defaults to the workflow actor |
| `registry-password-path` | No | empty | 1Password URI for the registry token. Empty means: GHCR uses the job's `github.token`, Docker Hub uses the Stone Home Docker PAT path |
| `onepass-token` | Only when a 1Password token is used | — | 1Password service-account token |
| `kubernetes-mode` | No | `false` | Use Kaniko at `/kaniko/executor` |
| `image-name` | No | GHCR caller repository | Image reference without a tag |
| `dockerfile` | No | `Dockerfile` | Dockerfile relative to the repository root |
| `context` | No | `.` | Build context relative to the repository root |
| `tags` | No | `latest` | Comma-separated tag suffixes |
| `git-clone` | No | `true` | In ARC mode, clone the current ref into the workspace |

Hosted GHCR example:

```yaml
permissions:
  contents: read
  packages: write

jobs:
  image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: stone-home/Action-Stone-DevOps/.github/actions/docker-push@trunk
        with:
          registry: ghcr
          image-name: ghcr.io/stone-home/example
          tags: latest,1.4.0
```

With no `registry-password-path`, GHCR pushes use the job's own `github.token`,
which needs `packages: write`. That token only reaches this repository's
packages and expires when the job ends. A package first created with a personal
token must grant this repository write access under the package's "Manage
Actions access" setting before the job token can push to it.

Prefer the job token in Kubernetes mode. Kaniko runs each Dockerfile `RUN` line
in the same filesystem that holds its registry login, so anything the image
build installs can read the push credential. A short-lived, single-repository
token limits what that is worth. Docker Hub has no job token, so give its token
the narrowest scope the registry offers.

For Docker Hub, set `registry: dockerhub`, an image such as
`username/project`, and the matching username and token path.

Kubernetes mode requires a runner or job container with
`/kaniko/executor`. If the caller has already checked out the repository, set
`git-clone: "false"`; the default clone expects an empty workspace. The
Dockerfile must be inside the selected build context.
