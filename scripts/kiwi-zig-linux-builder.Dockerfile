ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG CMAKE_VERSION=3.31.6
ARG ZIG_VERSION=0.15.2
ARG UV_VERSION=0.9.21

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    clang \
    curl \
    git \
    libblas-dev \
    liblapack-dev \
    liblapacke-dev \
    ninja-build \
    patchelf \
    pkg-config \
    python3 \
    unzip \
    xz-utils \
 && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
      arm64) cmake_arch='aarch64' ;; \
      amd64) cmake_arch='x86_64' ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && curl -fL --retry 5 --retry-all-errors --retry-delay 2 "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${cmake_arch}.tar.gz" -o /tmp/cmake.tar.gz \
 && tar -C /opt -xzf /tmp/cmake.tar.gz \
 && ln -s "/opt/cmake-${CMAKE_VERSION}-linux-${cmake_arch}/bin/cmake" /usr/local/bin/cmake \
 && rm /tmp/cmake.tar.gz \
 && cmake --version

RUN case "$TARGETARCH" in \
      arm64) zig_arch='aarch64' ;; \
      amd64) zig_arch='x86_64' ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && curl -fL --retry 5 --retry-all-errors --retry-delay 2 "https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
 && tar -C /opt -xf /tmp/zig.tar.xz \
 && ln -s "/opt/zig-${zig_arch}-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig \
 && rm /tmp/zig.tar.xz \
 && zig version

RUN curl -LsSf --retry 5 --retry-all-errors --retry-delay 2 "https://astral.sh/uv/${UV_VERSION}/install.sh" \
    | env UV_INSTALL_DIR=/usr/local/bin sh \
 && uv --version

WORKDIR /workspace
