FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Latest stable Bun via the official installer, installed system-wide.
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash \
 && bun --version
