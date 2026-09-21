# Site and Integration Actions

These actions deploy sites or write to external repositories and services. They
are more organization-specific than the setup and release actions.

## Site deployment

### `deploy-hugo-site`

Sets up Hugo Extended and Node.js, runs `npm ci`, builds with `hugo --minify`,
and publishes `public/` to the `gh-pages` branch.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `hugo-version` | No | `0.144.2` | Hugo version |
| `node-version` | No | `24` | Node.js version |
| `github-token-path` | No | Stone Home GitHub PAT path | Token used for the `gh-pages` push |
| `onepass-token` | Yes | — | 1Password service-account token |
| `kubernetes-mode` | No | `false` | Use ARC secret loading |

```yaml
permissions:
  contents: write

jobs:
  pages:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: stone-home/Action-Stone-DevOps/.github/actions/deploy-hugo-site@trunk
        with:
          hugo-version: "0.144.2"
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The repository needs a Hugo site and `package-lock.json`. The action pushes to
`gh-pages`; configure GitHub Pages to serve that branch.

### `deploy-mkdocs-site`

Sets up Python and Poetry, installs the `test` dependency group, runs
`poetry run mkdocs build`, and publishes `site/` to `gh-pages`.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `python-version` | No | `3.11` | Python version |
| `poetry-version` | No | `1.8.5` | Poetry version |
| `github-token-path` | No | Stone Home GitHub PAT path | Token used for the `gh-pages` push |
| `onepass-token` | Yes | — | 1Password service-account token |
| `kubernetes-mode` | No | `false` | Use ARC setup and secret loading |

```yaml
permissions:
  contents: write

jobs:
  pages:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: stone-home/Action-Stone-DevOps/.github/actions/deploy-mkdocs-site@trunk
        with:
          python-version: "3.12"
          poetry-version: "2.1.4"
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The caller needs `pyproject.toml`, `poetry.lock`, MkDocs configuration, and the
MkDocs dependencies in the installed groups.

## Organization integrations

### `create-blog-in-hugo`

Converts release metadata into a Hugo post, commits it, and pushes it to
`stonebo/stone-journey.github.io` on `trunk`. The target repository and branch
are fixed in the action. It also checks out this DevOps repository to run
`scripts/release_blog.py`.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `onepass-token` | Yes | — | 1Password service-account token |
| `release-subject` | Yes | — | Release title or version |
| `release-body` | Yes | — | Markdown release notes |
| `release-url` | Yes | — | Source release URL |
| `python-version` | Yes | `3.11` | Python version |
| `project-name` | Yes | — | Project label and output path segment |
| `hero-image` | No | `/images/posts/hero/project-release.jpeg` | Hugo hero image path |
| `github-token-path` | No | Personal GitHub Action PAT path | PAT with access to both private checkouts and the target push |
| `kubernetes-mode` | No | `false` | Use ARC secret loading and install Git |

Typical release trigger:

```yaml
name: Publish release blog

on:
  release:
    types: [published]

jobs:
  blog:
    runs-on: ubuntu-latest
    steps:
      - uses: stone-home/Action-Stone-DevOps/.github/actions/create-blog-in-hugo@trunk
        with:
          release-subject: ${{ github.event.release.name }}
          release-body: ${{ github.event.release.body }}
          release-url: ${{ github.event.release.html_url }}
          project-name: Example Project
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The action writes under `content/posts/project/<project>/<version>/` in the
Hugo repository and creates a project landing page when needed. A release with
no new commit-able content causes the current `git commit` step to fail.

### `obsidian-to-dify`

Checks out `stone-home/Python-RAG-Knowledge`, installs it with Poetry, and runs
its `main.py` uploader against a directory of notes. Dify API and Cloudflare
Access credentials are loaded from 1Password.

| Input | Required | Default | Meaning |
|---|---:|---|---|
| `onepass-token` | Yes | — | 1Password service-account token |
| `dify-url` | Yes | — | Dify server base URL |
| `target_dir_path` | Yes | — | Notes directory passed to the uploader |
| `python-version` | No | `3.11` | Python version |
| `poetry-version` | No | `2.1.4` | Poetry version |
| `github-token-path` | No | Stone Home GitHub PAT path | General PAT path; currently loaded by the action |
| `github-dify-repo-token` | No | Stone Home GitHub PAT path | Token for the private Python RAG checkout |
| `dify-api-token` | No | Stone Home Dify API path | Dify API credential path |
| `kubernetes-mode` | No | `false` | Use ARC setup and secret loading |

```yaml
jobs:
  upload:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: stone-home/Action-Stone-DevOps/.github/actions/obsidian-to-dify@trunk
        with:
          dify-url: https://dify.example.invalid
          target_dir_path: ${{ github.workspace }}/notes
          onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

The action also uses fixed 1Password paths for Cloudflare Access client ID and
secret. The runner and service account must be able to read those items. This is
a live upload path; validate the selected directory and Dify destination before
adding an automatic trigger.
