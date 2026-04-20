#!/usr/bin/env bash
# Workaround for PYCHARM_PYTHON_PATH being ignored in Ona.
#
# On PyCharm 2026.1, PySdkFromEnvironmentVariableConfigurator throws an EDT
# assertion; on 2025.2.x/2025.3.x it runs but hits a race where
# ModuleManager.getInstance(project).modules is empty at the moment the
# configurator iterates it, so the SDK is created in the global jdk.table.xml
# but never assigned to the project/module.
#
# This script sidesteps both bugs by pre-seeding jdk.table.xml for every
# currently-shipped PyCharm version. Combined with the .idea/misc.xml and
# .idea/<project>.iml in this repo (which reference the SDK by name
# "Python 3.12"), PyCharm picks up the interpreter on first open with no
# user action and no reliance on the broken configurator.

set -euo pipefail

PY_HOME="${PYCHARM_PYTHON_PATH:-/home/vscode/envs/app/bin/python}"
SDK_NAME="Python 3.12"

if [[ ! -x "${PY_HOME}" ]]; then
	echo "[seed-pycharm-sdk] ${PY_HOME} is not executable yet; skipping seed." >&2
	exit 0
fi

PY_VERSION=$("${PY_HOME}" -c 'import sys; print(f"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')
PY_MAJOR_MINOR=$("${PY_HOME}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_PREFIX=$("${PY_HOME}" -c 'import sys; print(sys.prefix)')

CONFIG_ROOT="${HOME}/.config/JetBrains"
mkdir -p "${CONFIG_ROOT}"

# Seed every PyCharm config dir that exists, plus the ones we know Ona ships.
# Creating the dir is cheap and harmless for versions the user never launches.
VERSIONS=(PyCharm2025.1 PyCharm2025.2 PyCharm2025.3 PyCharm2026.1)
for d in "${CONFIG_ROOT}"/PyCharm*; do
	[[ -d "$d" ]] || continue
	VERSIONS+=("$(basename "$d")")
done
# Dedupe.
mapfile -t VERSIONS < <(printf '%s\n' "${VERSIONS[@]}" | sort -u)

for v in "${VERSIONS[@]}"; do
	opts="${CONFIG_ROOT}/${v}/options"
	mkdir -p "${opts}"
	jdk_table="${opts}/jdk.table.xml"

	# If a jdk.table.xml already has our SDK entry, leave it alone.
	if [[ -f "${jdk_table}" ]] && grep -q "<name value=\"${SDK_NAME}\" />" "${jdk_table}"; then
		continue
	fi

	stubs="${HOME}/.cache/JetBrains/${v}/python_stubs/-seeded-${PY_MAJOR_MINOR}"
	mkdir -p "${stubs}"

	cat > "${jdk_table}" <<EOF
<application>
  <component name="ProjectJdkTable">
    <jdk version="2">
      <name value="${SDK_NAME}" />
      <type value="Python SDK" />
      <version value="${PY_VERSION}" />
      <homePath value="${PY_HOME}" />
      <roots>
        <classPath>
          <root type="composite">
            <root url="file://${PY_PREFIX}/lib/python${PY_MAJOR_MINOR}" type="simple" />
            <root url="file://${PY_PREFIX}/lib/python${PY_MAJOR_MINOR}/lib-dynload" type="simple" />
            <root url="file://${PY_PREFIX}/lib/python${PY_MAJOR_MINOR}/site-packages" type="simple" />
            <root url="file://${stubs}" type="simple" />
          </root>
        </classPath>
        <sourcePath>
          <root type="composite" />
        </sourcePath>
      </roots>
      <additional>
        <setting name="FLAVOR_ID" value="UnknownFlavor" />
        <setting name="FLAVOR_DATA" value="{}" />
      </additional>
    </jdk>
  </component>
</application>
EOF
	echo "[seed-pycharm-sdk] Seeded ${jdk_table}"
done
