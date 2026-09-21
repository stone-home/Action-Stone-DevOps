# Setup and Quality Actions

All paths below are relative to
`stone-home/Action-Stone-DevOps/.github/actions/` and examples use `@trunk`.
See [Getting started](getting-started.md) for private access, secrets, runner
modes, and permissions.

## Setup actions

### `setup-1password`

Configures the 1Password service-account action on a normal runner. In
Kubernetes mode it installs the `op` CLI and ensures `unzip` and CA certificates
exist.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `onepass-token` | Yes | — | 1Password service-account token |
| `kubernetes-mode` | No | `false` | Use the CLI-oriented ARC path |

```yaml
- uses: stone-home/Action-Stone-DevOps/.github/actions/setup-1password@trunk
  with:
    onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
    kubernetes-mode: "false"
```

This action configures access but does not read an item. Follow it with
`load-github-token` or another 1Password-aware action.

### `load-github-token`

Reads one value from any 1Password secret URI. Despite its historical name, the
value does not have to be a GitHub token.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `secret-path` | No | Stone Home GitHub PAT path | `op://...` item field to read |
| `kubernetes-mode` | No | `false` | Use `op read` instead of `load-secrets-action` |
| `onepass-token` | Only for Kubernetes mode | — | Service-account token passed to the CLI |

| Output | Meaning |
|---|---|
| `token` | Masked value read from the requested 1Password path |

On a normal runner, call `setup-1password` first:

```yaml
- uses: stone-home/Action-Stone-DevOps/.github/actions/setup-1password@trunk
  with:
    onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}

- id: registry-token
  uses: stone-home/Action-Stone-DevOps/.github/actions/load-github-token@trunk
  with:
    secret-path: op://DevOps/Docker PAT - Git Action/credential

- run: some-command
  env:
    REGISTRY_TOKEN: ${{ steps.registry-token.outputs.token }}
```

### `setup-nodejs`

Installs Node.js with `actions/setup-node` and runs `npm ci` by default.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `node-version` | No | `24` | Node.js version |
| `install-dependencies` | No | `true` | Run `npm ci` in the current workspace |

```yaml
- uses: actions/checkout@v6
- uses: stone-home/Action-Stone-DevOps/.github/actions/setup-nodejs@trunk
  with:
    node-version: "24"
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
sets up Python 3.12, and installs `ures==3.1.0`. It prepares dependencies; it
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

Runs a base Super-Linter pass and optional language-specific passes. It reads a
GitHub token from 1Password so status checks can be reported.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `python` | No | `false` | Add Black and notebook Black validation |
| `javascript` | No | `false` | Add JavaScript/TypeScript ESLint and Prettier validation |
| `latex` | No | `false` | Add LaTeX validation |
| `exclude` | No | `^test/` | Super-Linter exclusion regex |
| `github-token-path` | No | Stone Home GitHub PAT path | 1Password URI for status reporting |
| `onepass-token` | Yes | — | 1Password service-account token |
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
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

For Kubernetes mode, run the job in
`ghcr.io/super-linter/super-linter:v8.5.0`; the action expects the container's
`/action/lib/linter.sh` path. See `.github/workflows/s-linter.yaml` in this
repository for the working shape.

### `secret-check`

Scans Git history with TruffleHog. The normal path uses the marketplace Docker
action with `--fail`; the Kubernetes path installs the CLI when needed and runs
it directly.

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
| `node-version` | No | `24` | Node.js version |

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
