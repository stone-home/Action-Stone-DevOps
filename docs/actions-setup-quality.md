# Setup and Quality Actions

All paths below are relative to
`stone-home/Action-Stone-DevOps/.github/actions/` and examples use `@trunk`.
See [Getting started](getting-started.md) for private access, secrets, runner
modes, and permissions.

## Setup actions

### `setup-1password`

In Kubernetes mode it installs the `op` CLI and ensures `unzip`, `gpg`, and CA
certificates exist (`gpg` is used to verify the CLI's signature). On a normal
runner it does nothing.

It does not export the service-account token. The token is never written to the
job environment; `load-github-token` sets it on the single step that reads a
secret, so dependency installs, builds, and linters in the same job cannot read
it.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `onepass-token` | No | — | Deprecated and unused; pass the token to `load-github-token` |
| `kubernetes-mode` | No | `false` | Use the CLI-oriented ARC path |

```yaml
- uses: stone-home/Action-Stone-DevOps/.github/actions/setup-1password@trunk
  with:
    kubernetes-mode: "true"
```

A step that reads 1Password on its own after this action must set
`OP_SERVICE_ACCOUNT_TOKEN` in its own `env`.

### `load-github-token`

Reads one value from any 1Password secret URI. Despite its historical name, the
value does not have to be a GitHub token.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `secret-path` | No | Stone Home GitHub PAT path | `op://...` item field to read |
| `kubernetes-mode` | No | `false` | Use `op read` instead of `load-secrets-action` |
| `onepass-token` | Yes | — | Service-account token, set only on the step that reads the secret |

| Output | Meaning |
|---|---|
| `token` | Masked value read from the requested 1Password path |

In Kubernetes mode, call `setup-1password` first so the `op` CLI is installed.
On a normal runner this action is enough on its own:

```yaml
- id: registry-token
  uses: stone-home/Action-Stone-DevOps/.github/actions/load-github-token@trunk
  with:
    secret-path: op://DevOps/Docker PAT - Git Action/credential
    onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}

- run: some-command
  env:
    REGISTRY_TOKEN: ${{ steps.registry-token.outputs.token }}
```

### `setup-nodejs`

Installs Node.js with `actions/setup-node` and runs `npm ci` by default.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `node-version` | No | `26` | Node.js version |
| `install-dependencies` | No | `true` | Run `npm ci` in the current workspace |

```yaml
- uses: actions/checkout@v6
- uses: stone-home/Action-Stone-DevOps/.github/actions/setup-nodejs@trunk
  with:
    node-version: "26"
    install-dependencies: "true"
```

Set `install-dependencies: "false"` for repositories without `package-lock.json`
or when another step owns dependency installation.

### `setup-poetry`

Installs Python and Poetry, configures an in-project `.venv`, and caches that
virtual environment by runner OS, Python version, and `poetry.lock` hash.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `python-version` | Yes | `3.11` | Python version |
| `poetry-version` | Yes | `1.8.5` | Poetry version |
| `kubernetes-mode` | No | `false` | Install Poetry through `pipx` on ARC |

```yaml
- uses: actions/checkout@v6
- uses: stone-home/Action-Stone-DevOps/.github/actions/setup-poetry@trunk
  with:
    python-version: "3.12"
    poetry-version: "2.1.4"
    kubernetes-mode: "false"
- run: poetry install --with test
```

### `install-semantic-release`

Installs a pinned semantic-release toolchain into the current Node workspace,
sets up Python 3.12, and installs `ures==3.2.1`. It prepares dependencies; it
does not invoke `semantic-release` itself.

The installed Node packages are semantic-release 25.0.9 plus the exec, git,
GitHub, changelog, and npm plugins used by consumer configurations.

```yaml
- uses: actions/checkout@v6
- uses: stone-home/Action-Stone-DevOps/.github/actions/setup-nodejs@trunk
  with:
    install-dependencies: "false"
- uses: stone-home/Action-Stone-DevOps/.github/actions/install-semantic-release@trunk
- run: npx semantic-release
  env:
    GITHUB_TOKEN: ${{ secrets.RELEASE_TOKEN }}
```

## Quality actions

### `linter`

Runs a base Super-Linter pass and optional language-specific passes. It reports
status checks with the job's own `github.token` and reads nothing from
1Password, because linters execute configuration from the repository being
linted.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `python` | No | `false` | Add Black and notebook Black validation |
| `javascript` | No | `false` | Add JavaScript/TypeScript ESLint and Prettier validation |
| `latex` | No | `false` | Add LaTeX validation |
| `exclude` | No | `^test/` | Super-Linter exclusion regex |
| `github-token-path` | No | — | Deprecated and unused |
| `onepass-token` | No | — | Deprecated and unused |
| `kubernetes-mode` | No | `false` | Call `/action/lib/linter.sh` instead of the Docker action |

```yaml
permissions:
  contents: read
  packages: read
  statuses: write

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: stone-home/Action-Stone-DevOps/.github/actions/linter@trunk
        with:
          python: "true"
          javascript: "false"
          exclude: ^(test/|vendor/)
```

For Kubernetes mode, run the job in
`ghcr.io/super-linter/super-linter:v8.7.0`; the action expects the container's
`/action/lib/linter.sh` path. See `.github/workflows/s-linter.yaml` in this
repository for the working shape.

### `secret-check`

Scans Git history with TruffleHog 3.100.0 and fails the job when a verified or
unknown secret is found. The normal path uses the marketplace Docker action at a
pinned commit; the Kubernetes path installs that same version, checks the
download against a pinned SHA-256, and runs it with `--fail`.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `kubernetes-mode` | No | `false` | Use the ARC shell implementation |

```yaml
permissions:
  contents: read

jobs:
  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: stone-home/Action-Stone-DevOps/.github/actions/secret-check@trunk
```

The current Kubernetes command does not pass `--fail`, while the normal action
does. Treat its result as scan output unless the runner's TruffleHog defaults
make findings fatal.

### `nodejs-test`

Calls `setup-nodejs`, which runs `npm ci`, then runs `npm test`.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `node-version` | No | `26` | Node.js version |

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: stone-home/Action-Stone-DevOps/.github/actions/nodejs-test@trunk
        with:
          node-version: "22"
```

The caller needs a committed `package-lock.json` and an `npm test` script.

### `python-poetry-test`

Sets up Poetry, installs the project with the `test` dependency group, and runs
`pytest -v`.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `python-version` | No | `3.12` | Python version |
| `poetry-version` | No | `2.1.4` | Poetry version |

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: stone-home/Action-Stone-DevOps/.github/actions/python-poetry-test@trunk
        with:
          python-version: "3.12"
          poetry-version: "2.1.4"
```

The caller needs `pyproject.toml`, `poetry.lock`, a `test` dependency group, and
pytest configuration. This action currently exposes no `kubernetes-mode` input.
