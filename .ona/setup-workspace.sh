#!/usr/bin/env bash
# Create a named conda env so PYCHARM_PYTHON_PATH points at something real.
# Mirrors the customer's pattern: /home/<user>/envs/<project>/bin/python
set -euo pipefail

ENV_NAME="app"
ENV_PATH="/home/vscode/envs/${ENV_NAME}"

if [ ! -x "${ENV_PATH}/bin/python" ]; then
	echo "Creating conda env at ${ENV_PATH} ..."
	mkdir -p "/home/vscode/envs"
	conda create -y -p "${ENV_PATH}" python=3.12
fi

"${ENV_PATH}/bin/python" --version
echo "PYCHARM_PYTHON_PATH target: ${ENV_PATH}/bin/python"
