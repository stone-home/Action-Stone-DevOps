# Repository Maintenance

## Repository workflows

The `s-*` workflows operate this repository. Consumers should reference the
reusable workflows without the `s-` prefix or call a composite action directly.

| File | Trigger | What it does |
|---|---|---|
| `s-linter.yaml` | Pushes except `trunk`, and pull requests | Runs the local `linter` action on `arc-runner-large` in the Super-Linter container |
| `s-release.yaml` | Manual dispatch | Checks out full history and invokes the local `publish-basic` action |
| `s-publish-blog.yaml` | Published release | Invokes the local `create-blog-in-hugo` action for this project's release notes |

The other workflow files expose `workflow_call` and are consumer-facing.

## Source layout

- `.github/actions/<name>/action.yaml` defines one composite action.
- `.github/workflows/*.yaml` defines reusable and repository workflows.
- `scripts/latex/` owns the current LaTeX build and comparison implementation.
- `scripts/release_blog.py` is used by `create-blog-in-hugo`.
- `scripts/create_blog.py` is an older release-post generator and is not called
  by the current action.
- `test/run-tests.sh` exercises LaTeX parsing, builds, isolated bibliographies,
  release downloads, and main/appendix diffs with local fixtures and a curl stub.

## Change checklist

When changing a composite action:

1. Keep its `action.yaml` inputs, defaults, outputs, and internal references in
   sync with the implementation.
2. Update the matching section in the action reference document and the root
   catalog if its purpose or name changed.
3. Update every reusable workflow that forwards the changed input.
4. Check hosted and Kubernetes branches separately when both exist.

When changing a reusable workflow:

1. Keep `workflow_call.inputs` and `workflow_call.secrets` compatible with
   existing callers, or document the breaking change.
2. Update its complete input table and example.
3. Check that caller permissions can satisfy every enabled job.
4. If it calls actions by `@trunk`, confirm the selected revision contains the
   required action interface.

When changing LaTeX scripts:

1. Update [LaTeX release](latex-release.md), including artifact names.
2. Add or update a fixture-backed case in `test/run-tests.sh` when behavior
   changes.
3. Run the suite and report skipped tool-dependent cases separately from passes.

## Validation

Run the offline LaTeX suite:

```bash
bash test/run-tests.sh
```

Parse every action and workflow manifest:

```bash
python - <<'PY'
from pathlib import Path
import yaml
paths = [
    *Path('.github/actions').glob('*/action.y*ml'),
    *Path('.github/workflows').glob('*.y*ml'),
]
for path in paths:
    yaml.safe_load(path.read_text())
    print(f"OK {path}")
PY
```

Also check documentation links, shell syntax, and whitespace:

```bash
for file in scripts/latex/*.sh test/run-tests.sh; do bash -n "$file"; done
git diff --check
```

Actual release, deployment, registry, 1Password, ARC, and Dify behavior requires
an authorized integration run. Local syntax and smoke tests do not prove those
external paths.
