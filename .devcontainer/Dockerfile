FROM mcr.microsoft.com/devcontainers/miniconda:1-3

ENV CONDA_ENVS_PATH="/home/vscode/envs"
ENV PATH="/home/vscode/envs/app/bin:/opt/conda/bin:/opt/conda/condabin:$PATH"
ENV PYCHARM_PYTHON_PATH="/home/vscode/envs/app/bin/python"

USER vscode
COPY setup-workspace.sh /tmp
RUN bash /tmp/setup-workspace.sh