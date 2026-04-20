# pycharm-regression

Minimal repro for Pylon #27861: `PYCHARM_PYTHON_PATH` is not picked up as the PyCharm interpreter in Ona.

## Summary

`PYCHARM_PYTHON_PATH` is broken in Ona across **every currently-shipped PyCharm version** (2025.2.6, 2025.3.4, 2026.1), but for **two different reasons**:

| Version | Status | Root cause |
|---|---|---|
| 2026.1 (PY-261.22158.340) | Throws `IllegalStateException: Access is allowed from Event Dispatch Thread (EDT) only` | JetBrains refactored `PySdkFromEnvironmentVariableConfigurator` from `runInEdt {}` to a coroutine on `Dispatchers.Default` (PY-88280 / PY-88216 / PY-88517). `SdkConfigurationUtil.createAndAddSDK` internally calls `WriteAction.compute {}` which still requires the EDT, so SDK creation crashes. |
| 2025.3.4 (PY-253.x) | SDK created in `jdk.table.xml` but never assigned to project/module. UI shows "No interpreter". | In remote-dev mode, `JpsProjectLoadedListener.loaded()` fires before modules are committed to `ModuleManager`. The configurator's `runInEdt { ModuleManager.getInstance(project).modules.forEach { ... } }` iterates an empty module list, so `setModuleSdk` never runs. `module.pythonSdk`/`project.pythonSdk` are never assigned, `.idea/misc.xml` is never written. |
| 2025.2.6 (PY-252.28539.27) | Same as 2025.3.4 | Same race as above. |

The 2026.1 EDT bug is a fresh regression. The 2025.x race appears to be a pre-existing latent bug in JetBrains Remote Development that only manifests for projects that don't already have `.idea/misc.xml` committed — i.e. first open on a clean clone, which is exactly the Ona flow.

## Verified workaround (in this repo)

This repo ships with a workaround that sidesteps **both** bugs. It does three things:

1. Commits `.idea/misc.xml` with `project-jdk-name="Python 3.12"` so the project SDK assignment doesn't depend on the broken configurator.
2. Commits `.idea/pycharm-regression.iml` with an explicit `<orderEntry type="jdk" jdkName="Python 3.12" jdkType="Python SDK" />` so the module SDK assignment also doesn't depend on the configurator.
3. Runs `.ona/seed-pycharm-sdk.sh` on every container start (`postStartCommand`). The script writes `~/.config/JetBrains/PyCharm<version>/options/jdk.table.xml` for every currently-shipped PyCharm version (2025.1, 2025.2, 2025.3, 2026.1), registering a global SDK called `Python 3.12` that points at `$PYCHARM_PYTHON_PATH`.

With those three pieces in place, when PyCharm opens the project:
- It reads `.idea/misc.xml` → project SDK name = `Python 3.12`
- It reads `.idea/pycharm-regression.iml` → module SDK name = `Python 3.12`
- It resolves `Python 3.12` against `jdk.table.xml` → finds the pre-seeded entry pointing at the conda interpreter
- The interpreter is configured before the broken configurator ever runs

The seed script is idempotent (skips versions whose `jdk.table.xml` already has the entry) and harmless for versions the user never launches.

## How to verify the bug without the workaround

1. Revert the workaround files:
   - `rm .idea/misc.xml`
   - Replace `.idea/pycharm-regression.iml` with `<orderEntry type="inheritedJdk" />`
   - Remove `postStartCommand` from `.devcontainer/devcontainer.json`
2. Open this repo in an Ona environment.
3. Open PyCharm via the action bar (try 2026.1, 2025.3, and 2025.2 in turn).
4. **Expected**: interpreter auto-selected as `/home/vscode/envs/app/bin/python`.
5. **Actual**: "No interpreter configured for the project" in all three versions.

## Diagnostics to capture

On the PyCharm backend (inside the Ona env via SSH), open the log:

```bash
# 2026.1: look for the EDT crash
grep -iE 'pycharm_python_path|pysdkfromenvironment|Access is allowed from Event Dispatch' \
  ~/.cache/JetBrains/PyCharm2026.1/log/idea.log

# 2025.x: look for the silent-failure signature
#   - "Found ... PYCHARM_PYTHON_PATH='...' system property"  -> configurator fired
#   - "No suitable sdk found, created a new one"             -> SDK added to jdk.table.xml
#   - grep -c 'Setting PythonSDK' ...                        -> should be 0 if the bug hit
grep -iE 'pycharm_python_path|pysdkfromenvironment|Setting PythonSDK|No suitable sdk' \
  ~/.cache/JetBrains/PyCharm2025.3/log/idea.log
grep -c 'Setting PythonSDK' ~/.cache/JetBrains/PyCharm2025.3/log/idea.log
```

## Context

Related JetBrains commits in `JetBrains/intellij-community` touching `PySdkFromEnvironmentVariableConfigurator` in the weeks before 2026.1 shipped (2026-03-30):

- `8248618a` (2026-03-18) PY-88280: converted configurator from `runInEdt` to coroutine on `Dispatchers.Default` with `pythonSdkConfigurationMutex`.
- `572e74c2` (2026-03-23) PY-88517: per-project mutex.
- `af615882` (2026-03-27) PY-88216: wrap mutex in modal progress to fix deadlock.
- `374adda0` (2026-03-30) PY-88280: EDT assertion fix, same file.

The YouTrack tickets above are private. The 2025.x race is not covered by any of them — it appears to be a separate, older bug.
