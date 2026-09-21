# Action Stone DevOps

Private GitHub Actions automation for Stone Home repositories. This repository
contains reusable workflows, composite actions, and a tested LaTeX release
toolchain.

## Choose an entry point

| Goal | Start here |
|---|---|
| Release a Python, Node.js, LaTeX, Docker, or basic project | [Comprehensive release workflow](docs/workflows-release.md#comprehensive-release-gateway) |
| Add tests, linting, or secret scanning | [Quality actions](docs/actions-setup-quality.md#quality-actions) or [quality workflows](docs/workflows-quality-sites.md#quality-workflows) |
| Deploy Hugo or MkDocs to GitHub Pages | [Site actions](docs/actions-sites-integrations.md#site-deployment) |
| Publish release notes to the Stone blog | [`create-blog-in-hugo`](docs/actions-sites-integrations.md#create-blog-in-hugo) |
| Upload Obsidian notes to Dify | [`obsidian-to-dify`](docs/actions-sites-integrations.md#obsidian-to-dify) |
| Configure a LaTeX semantic release | [LaTeX release guide](docs/latex-release.md) |
| Maintain this automation repository | [Repository maintenance](docs/maintenance.md) |

Read [Getting started](docs/getting-started.md) before adding an integration. It
covers private-repository access, secrets, permissions, runner modes, and ref
selection.

## Minimal reusable-workflow example

The comprehensive gateway is the normal release entry point. This example runs
a basic semantic release when manually dispatched:

```yaml
name: Release

on:
  workflow_dispatch:

permissions:
  contents: write
  issues: write
  pull-requests: write
  id-token: write

jobs:
  release:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/w-v2-release.yaml@trunk
    with:
      default-branch: trunk
    secrets:
      onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

Enable a project-specific job with `python-project`, `nodejs-project`,
`latex-project`, or `docker-push`. Multiple true values create multiple jobs.
See the [release workflow reference](docs/workflows-release.md) for complete
inputs and examples.

## Composite action catalog

Use a composite action inside `jobs.<job>.steps`. High-level actions configure
their own runtime and 1Password access; setup actions are building blocks for
custom jobs.

### Setup and quality

| Action | Purpose | Usage and example |
|---|---|---|
| [`setup-1password`](.github/actions/setup-1password/action.yaml) | Configure the 1Password action or CLI | [Docs](docs/actions-setup-quality.md#setup-1password) |
| [`load-github-token`](.github/actions/load-github-token/action.yaml) | Read one secret from a 1Password URI and expose `token` | [Docs](docs/actions-setup-quality.md#load-github-token) |
| [`setup-nodejs`](.github/actions/setup-nodejs/action.yaml) | Install Node.js and optionally run `npm ci` | [Docs](docs/actions-setup-quality.md#setup-nodejs) |
| [`setup-poetry`](.github/actions/setup-poetry/action.yaml) | Install Python and Poetry and cache `.venv` | [Docs](docs/actions-setup-quality.md#setup-poetry) |
| [`install-semantic-release`](.github/actions/install-semantic-release/action.yaml) | Install the pinned semantic-release toolchain and `ures` | [Docs](docs/actions-setup-quality.md#install-semantic-release) |
| [`linter`](.github/actions/linter/action.yaml) | Run base, Python, JavaScript/TypeScript, and LaTeX Super-Linter checks | [Docs](docs/actions-setup-quality.md#linter) |
| [`secret-check`](.github/actions/secret-check/action.yaml) | Scan Git history with TruffleHog | [Docs](docs/actions-setup-quality.md#secret-check) |
| [`nodejs-test`](.github/actions/nodejs-test/action.yaml) | Run `npm ci` and `npm test` | [Docs](docs/actions-setup-quality.md#nodejs-test) |
| [`python-poetry-test`](.github/actions/python-poetry-test/action.yaml) | Install Poetry dependencies and run pytest | [Docs](docs/actions-setup-quality.md#python-poetry-test) |

### Release and publishing

| Action | Purpose | Usage and example |
|---|---|---|
| [`publish-basic`](.github/actions/publish-basic/action.yaml) | Run semantic-release for a generic repository | [Docs](docs/actions-release.md#publish-basic) |
| [`publish-npm`](.github/actions/publish-npm/action.yaml) | Build a Node package and run semantic-release/npm publication | [Docs](docs/actions-release.md#publish-npm) |
| [`publish-python`](.github/actions/publish-python/action.yaml) | Create a version branch, build with Poetry, and optionally publish to PyPI | [Docs](docs/actions-release.md#publish-python) |
| [`publish-latex`](.github/actions/publish-latex/action.yaml) | Install TeX and run the consumer's semantic-release configuration | [Docs](docs/actions-release.md#publish-latex) |
| [`docker-push`](.github/actions/docker-push/action.yaml) | Build and push with Docker or Kaniko | [Docs](docs/actions-release.md#docker-push) |

### Sites and integrations

| Action | Purpose | Usage and example |
|---|---|---|
| [`deploy-hugo-site`](.github/actions/deploy-hugo-site/action.yaml) | Build Hugo and publish `public/` to `gh-pages` | [Docs](docs/actions-sites-integrations.md#deploy-hugo-site) |
| [`deploy-mkdocs-site`](.github/actions/deploy-mkdocs-site/action.yaml) | Build MkDocs with Poetry and publish `site/` | [Docs](docs/actions-sites-integrations.md#deploy-mkdocs-site) |
| [`create-blog-in-hugo`](.github/actions/create-blog-in-hugo/action.yaml) | Create and push a release post to the Stone Hugo repository | [Docs](docs/actions-sites-integrations.md#create-blog-in-hugo) |
| [`obsidian-to-dify`](.github/actions/obsidian-to-dify/action.yaml) | Upload notes through the private Python RAG project | [Docs](docs/actions-sites-integrations.md#obsidian-to-dify) |

## Workflow catalog

Reusable workflows are called at the job level, not from `steps`.

| Workflow | Type | Purpose | Usage and example |
|---|---|---|---|
| [`w-v2-release.yaml`](.github/workflows/w-v2-release.yaml) | Reusable | Comprehensive release gateway | [Docs](docs/workflows-release.md#comprehensive-release-gateway) |
| [`release.yaml`](.github/workflows/release.yaml) | Reusable | Earlier semantic-release gateway for basic, Node, or LaTeX projects | [Docs](docs/workflows-release.md#releaseyaml) |
| [`poetry-publish.yaml`](.github/workflows/poetry-publish.yaml) | Reusable | Standalone Poetry version branch and PyPI publication | [Docs](docs/workflows-release.md#poetry-publishyaml) |
| [`pytest.yaml`](.github/workflows/pytest.yaml) | Reusable | Poetry install and pytest | [Docs](docs/workflows-quality-sites.md#pytestyaml) |
| [`linter.yaml`](.github/workflows/linter.yaml) | Reusable | Hosted Super-Linter workflow | [Docs](docs/workflows-quality-sites.md#linteryaml) |
| [`secret-check.yaml`](.github/workflows/secret-check.yaml) | Reusable | Hosted TruffleHog scan | [Docs](docs/workflows-quality-sites.md#secret-checkyaml) |
| [`gh_page_publish.yaml`](.github/workflows/gh_page_publish.yaml) | Reusable | Hugo and/or MkDocs GitHub Pages deployment | [Docs](docs/workflows-quality-sites.md#gh_page_publishyaml) |
| [`create_release_blog.yaml`](.github/workflows/create_release_blog.yaml) | Reusable | Earlier release-to-blog workflow | [Docs](docs/workflows-quality-sites.md#create_release_blogyaml) |
| [`s-linter.yaml`](.github/workflows/s-linter.yaml) | Repository | Lint this repository on branches and pull requests | [Docs](docs/maintenance.md#repository-workflows) |
| [`s-release.yaml`](.github/workflows/s-release.yaml) | Repository | Manually release this repository | [Docs](docs/maintenance.md#repository-workflows) |
| [`s-publish-blog.yaml`](.github/workflows/s-publish-blog.yaml) | Repository | Publish this repository's release notes to the Stone blog | [Docs](docs/maintenance.md#repository-workflows) |

## Repository layout

```text
.github/actions/       Composite actions used directly or by workflows
.github/workflows/     Reusable workflows and this repository's s-* workflows
scripts/latex/         Standalone LaTeX build, diff, and release scripts
scripts/*.py           Hugo release-post generators
test/                  Offline smoke tests for the LaTeX scripts
docs/                  Consumer and maintainer documentation
```

The original development-conventions article remains useful background:
[Stone's development conventions](https://stonebo.github.io/stone-journey.github.io/posts/dev/conventions/).
It is supplementary context rather than the usage guide for this repository.

## Local checks

```bash
bash test/run-tests.sh
python - <<'PY'
from pathlib import Path
import yaml
for path in [*Path('.github/actions').glob('*/action.y*ml'), *Path('.github/workflows').glob('*.y*ml')]:
    yaml.safe_load(path.read_text())
print('YAML parsed successfully')
PY
```

The LaTeX suite skips cases whose local toolchain is unavailable and reports
those skips separately. See [Repository maintenance](docs/maintenance.md) for
the full review checklist.
