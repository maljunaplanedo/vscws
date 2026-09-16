FROM mcr.microsoft.com/devcontainers/base:ubuntu

# uv (environments and packages) and ruff (lint and format): latest stable, system-wide.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh \
 && curl -LsSf https://astral.sh/ruff/install.sh | env RUFF_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh \
 && uv --version && ruff --version
