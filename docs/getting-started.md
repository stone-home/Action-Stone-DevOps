# Getting Started

This is a private automation repository. A consuming repository must be allowed
to download its actions and reusable workflows before any example here can run.

## 1. Allow private reuse

In this repository's GitHub settings, open **Actions → General → Access** and
allow the intended Stone Home repositories to use its actions and reusable
workflows. The caller repository must also permit the referenced actions under
its own Actions policy.

GitHub documents the private sharing model in
[Sharing actions and workflows with your organization](https://docs.github.com/en/actions/how-tos/reuse-automations/share-with-your-organization).

## 2. Choose between an action and a workflow

A composite action belongs inside a job's `steps`:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: stone-home/Action-Stone-DevOps/.github/actions/nodejs-test@trunk
```

A reusable workflow replaces the job body and is referenced by
`jobs.<job>.uses`:

```yaml
jobs:
  test:
    uses: stone-home/Action-Stone-DevOps/.github/workflows/pytest.yaml@trunk
    with:
      python-version: "3.12"
      poetry-version: "2.1.4"
```

A job that calls a reusable workflow cannot also declare `runs-on` or `steps`.

## 3. Configure 1Password

Most publishing, deployment, and linting entry points expect a 1Password
service-account token. Store it in the caller repository as
`OP_ACCOUNT_TOKEN`, then pass it only through `secrets` or an action input:

```yaml
# Reusable workflow
secrets:
  onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

```yaml
# Composite action
with:
  onepass-token: ${{ secrets.OP_ACCOUNT_TOKEN }}
```

Secret values stay in GitHub Secrets. The documented `op://...` values are
1Password item paths and may be overridden with the relevant `*-token-path` or
`secret-path` input.

## 4. Grant the required permissions

Start with the smallest set required by the selected component.

| Operation | Typical job or workflow permission |
|---|---|
| Checkout, tests, or secret scan | `contents: read` |
| Super-Linter status reporting | `contents: read`, `packages: read`, `statuses: write` |
| GitHub release or version branch | `contents: write`; semantic-release may also need `issues: write` and `pull-requests: write` |
| Push an image to GHCR | `contents: read`, `packages: write` |
| Trusted publication | `id-token: write` plus the package registry's trusted-publisher configuration |

A called workflow cannot increase permissions beyond those granted by its
caller. The comprehensive release example therefore declares all permissions
its possible jobs may need.

## 5. Select a runner mode

Most composite actions accept `kubernetes-mode` as the strings `"true"` or
`"false"`.

- `"false"` uses normal Docker-based marketplace actions on a hosted or
  Docker-capable runner.
- `"true"` uses shell or CLI paths intended for Actions Runner Controller
  containers. The runner image must contain the tools named by the action.

Special requirements:

- `linter` in Kubernetes mode expects Super-Linter's `/action/lib/linter.sh`.
  The repository workflow demonstrates this with the Super-Linter container.
- `docker-push` in Kubernetes mode expects `/kaniko/executor`; setting the flag
  does not install Kaniko.
- `python-poetry-test` does not declare a `kubernetes-mode` input and should be
  treated as a hosted-runner action.

Reusable-workflow booleans such as `python-project` are YAML booleans. Composite
Action inputs are strings, so use `"true"` and `"false"` in `with` blocks.

## 6. Choose a ref

Examples use `@trunk` because that is the repository's active integration ref.
For a stable consumer, replace it with a release tag or full commit SHA after
that revision is available. Update all references for one integration together;
a reusable workflow can call composite actions from a different ref if its
source hard-codes one.

## 7. Understand side effects

These components perform real writes:

- release actions create tags, releases, branches, commits, or registry uploads;
- deployment actions push `gh-pages`;
- `create-blog-in-hugo` commits to the Stone Hugo repository;
- `obsidian-to-dify` sends documents to a configured Dify service;
- Docker and package publishers upload external artifacts.

Use test repositories or dry-run facilities in the underlying toolchain before
adding a production trigger. The YAML examples show configuration; they do not
replace repository-specific release rules, package registry setup, or protected
branch policy.
