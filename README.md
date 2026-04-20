# pycharm-regression

Minimal repro for Pylon #27861: `PYCHARM_PYTHON_PATH` is no longer picked up as the PyCharm interpreter after PyCharm 2026.1.

## What this exercises

- `.devcontainer/devcontainer.json` sets `PYCHARM_PYTHON_PATH` via `containerEnv`, pointing at `/home/vscode/envs/app/bin/python`.
- `.ona/setup-workspace.sh` (run via `onCreateCommand`) creates that conda env so the path is real before PyCharm connects.
- `main.py` gives PyCharm something to index.

This mirrors the structure of the customer's `devcontainer.json` without any of their private Artifactory dependencies.

## How to reproduce

1. Open this repo in an Ona environment.
2. Open it in PyCharm Professional via the action bar.
3. After the backend downloads and the project loads, check the status bar interpreter selector.
4. **Expected (pre-2026.1)**: interpreter auto-selected as `/home/vscode/envs/app/bin/python`.
5. **Actual (2026.1)**: "No interpreter" — must be set manually.

## What to capture

On the PyCharm **backend** (inside the Ona environment), open the log:

```bash
# path varies slightly; match the PY-* prefix
tail -n +1 ~/.cache/JetBrains/RemoteDev-PY*/*/log/idea.log | grep -iE 'pycharm_python_path|pysdkfromenvironment|sdkconfiguration'
```

What to look for:

- `Found PySdkFromEnvironmentVariable.PYCHARM_PYTHON_PATH='...' system property`
  → configurator fires; SDK assignment likely failing later (matches hypothesis: regression from JetBrains PY-88280 / PY-88216 / PY-88517 mutex-and-coroutine rewrite that shipped in 2026.1).
- Line absent → env var isn't reaching the PyCharm backend process (different root cause; points at the CWM→Remote Development launcher in our plugin change #18870).

Also capture:

- `Help → About` → PyCharm backend version (expect `2026.1 (261.22158.340)` or later).
- Output of `env | grep PYCHARM` in the workspace terminal (should show the env var set).

## Context

Related JetBrains commits in `JetBrains/intellij-community` touching `PySdkFromEnvironmentVariableConfigurator` in the weeks before 2026.1 shipped (2026-03-30):

- `8248618a` (2026-03-18) PY-88280: converted configurator from `runInEdt` to coroutine on `Dispatchers.Default` with `pythonSdkConfigurationMutex`.
- `572e74c2` (2026-03-23) PY-88517: per-project mutex.
- `af615882` (2026-03-27) PY-88216: wrap mutex in modal progress to fix deadlock.
- `374adda0` (2026-03-30) PY-88280: EDT assertion fix, same file.

The YouTrack tickets are private. The regression plausibly shipped in 2026.1 stable.
