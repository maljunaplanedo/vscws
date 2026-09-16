FROM mcr.microsoft.com/devcontainers/base:ubuntu

# uv (environments, packages, Python versions) and ruff (lint and format): latest stable, system-wide.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
 && curl -LsSf https://astral.sh/ruff/install.sh | env RUFF_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh \
 && uv --version && ruff --version

# Latest stable CPython as a prebuilt python-build-standalone build (no compilation), available to every user.
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python UV_PYTHON_BIN_DIR=/usr/local/bin uv python install --default && chmod -R a+rX /opt/uv && python3 --version && python --version
