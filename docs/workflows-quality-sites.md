# Quality and Site Workflows

These reusable workflows provide single-purpose job entry points. Call them at
`jobs.<job>.uses`.

## Quality workflows

### `pytest.yaml`

Checks out full history, installs Python and Poetry, creates an in-project
`.venv`, installs the `test` group, and runs `pytest -v`.

| Input | Type | Default |
|---|---|---|
| `python-version` | string | `3.11` |
| `poetry-version` | string | `1.8.5` |

```yaml
jobs:
  test:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/pytest.yaml@trunk
    with:
      python-version: "3.12"
      poetry-version: "2.1.4"
```

### `linter.yaml`

Runs the hosted Super-Linter 7.2.1 base checks and optionally Python Black
checks. It loads a fixed GitHub PAT path from 1Password for status reporting.

| Input | Type | Default | Meaning |
|---|---|---|---|
| `python` | boolean | `false` | Add Python and notebook Black checks |
| `exclude` | string | `^test/` | Exclusion regex |

| Secret | Required |
|---|---:|
| `onepass_token` | Yes |

```yaml
permissions:
  contents: read
  packages: read
  statuses: write

jobs:
  lint:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/linter.yaml@trunk
    with:
      python: true
      exclude: ^(test/|vendor/)
    secrets:
      onepass_token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

Use the `linter` composite action when JavaScript, TypeScript, LaTeX, custom
secret paths, or Kubernetes mode is needed.

### `secret-check.yaml`

Checks out full history and scans it with `trufflesecurity/trufflehog@main`.
It declares no inputs or secrets.

```yaml
permissions:
  contents: read

jobs:
  secrets:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/secret-check.yaml@trunk
```

The workflow requests verified and unknown results but does not explicitly pass
`--fail`. Use the `secret-check` composite action's normal-runner path when a
finding must explicitly fail the job.

## Page deployment workflow

### `gh_page_publish.yaml`

Provides separate Hugo and MkDocs jobs. Set at least one page flag to true; both
may be true and will run independently.

| Input | Type | Default | Meaning |
|---|---|---|---|
| `hugo-page` | boolean | `false` | Build and deploy Hugo |
| `mkdocs-page` | boolean | `false` | Build and deploy MkDocs |
| `hugo-version` | string | `0.144.2` | Hugo Extended version |
| `python-version` | string | `3.11` | MkDocs Python version |
| `poetry-version` | string | `1.8.5` | MkDocs Poetry version |
| `github-token-path` | string | Stone Home GitHub PAT path | Token URI for `gh-pages` pushes |

| Secret | Required |
|---|---:|
| `onepass_token` | Yes |

Hugo example:

```yaml
permissions:
  contents: write

jobs:
  pages:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/gh_page_publish.yaml@trunk
    with:
      hugo-page: true
      hugo-version: "0.144.2"
    secrets:
      onepass_token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The Hugo job runs `hugo mod tidy`, packages Hugo modules for npm, runs
`npm install`, builds `public/`, and pushes `gh-pages`.

MkDocs example:

```yaml
permissions:
  contents: write

jobs:
  pages:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/gh_page_publish.yaml@trunk
    with:
      mkdocs-page: true
      python-version: "3.12"
      poetry-version: "2.1.4"
    secrets:
      onepass_token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The MkDocs job installs the Poetry `test` group, builds `site/`, and pushes
`gh-pages`.

## Release blog workflow

### `create_release_blog.yaml`

This earlier hosted-runner workflow writes a release post to the fixed
`stonebo/stone-journey.github.io` repository. It performs the same organization
integration as the newer composite action but embeds the steps in the workflow.

| Input | Type | Required/default |
|---|---|---|
| `release-subject` | string | required |
| `release-body` | string | required |
| `release-url` | string | required |
| `python-version` | string | default `3.11` |
| `project-name` | string | required |
| `hero-image` | string | default `/images/posts/hero/project-release.jpeg` |

| Secret | Required |
|---|---:|
| `onepass_token` | Yes |

```yaml
name: Publish release blog

on:
  release:
    types: [published]

jobs:
  blog:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/create_release_blog.yaml@trunk
    with:
      release-subject: ${{ github.event.release.name }}
      release-body: ${{ github.event.release.body }}
      release-url: ${{ github.event.release.html_url }}
      project-name: Example Project
    secrets:
      onepass_token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

Use the [`create-blog-in-hugo` composite action](actions-sites-integrations.md#create-blog-in-hugo)
when Kubernetes mode, a custom GitHub-token path, or composition with other
steps in the same job is required.
