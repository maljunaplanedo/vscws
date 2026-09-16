FROM mcr.microsoft.com/devcontainers/base:ubuntu

ENV DEBIAN_FRONTEND=noninteractive

# GCC toolchain and common build tools from Ubuntu.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential gdb ninja-build ccache pkg-config make \
      wget gnupg lsb-release software-properties-common \
 && rm -rf /var/lib/apt/lists/*

# Latest stable LLVM from apt.llvm.org (no version argument = current stable).
# Falls back to Ubuntu's own packages if apt.llvm.org has no repo for this Ubuntu release yet.
RUN set -e; \
    wget -qO /tmp/llvm.sh https://apt.llvm.org/llvm.sh && chmod +x /tmp/llvm.sh; \
    if ! /tmp/llvm.sh all; then \
      echo "apt.llvm.org has no packages for this release; using Ubuntu's LLVM packages"; \
      rm -f /etc/apt/sources.list.d/*llvm* /etc/apt/sources.list.d/archive_uri-*; \
      apt-get update && apt-get install -y --no-install-recommends clang clangd clang-format clang-tidy lldb lld; \
    fi; \
    rm -f /tmp/llvm.sh; rm -rf /var/lib/apt/lists/*; \
    v="$(ls -d /usr/lib/llvm-* 2>/dev/null | sed 's#.*/llvm-##' | sort -n | tail -1)"; \
    if [ -n "$v" ]; then \
      for t in clang clang++ clangd clang-format clang-tidy lldb lld ld.lld llvm-symbolizer; do \
        if [ -x "/usr/bin/$t-$v" ]; then ln -sf "/usr/bin/$t-$v" "/usr/local/bin/$t"; fi; \
      done; \
    fi; \
    clang --version && clangd --version

# Latest stable CMake: official binaries from Kitware's GitHub releases (x86_64 and aarch64).
RUN set -e; \
    v="$(wget -qO- https://api.github.com/repos/Kitware/CMake/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')"; \
    arch="$(uname -m)"; \
    wget -qO /tmp/cmake.tar.gz "https://github.com/Kitware/CMake/releases/download/v${v}/cmake-${v}-linux-${arch}.tar.gz"; \
    mkdir -p /opt/cmake && tar -xzf /tmp/cmake.tar.gz -C /opt/cmake --strip-components=1 && rm /tmp/cmake.tar.gz; \
    ln -sf /opt/cmake/bin/* /usr/local/bin/; \
    cmake --version
