FROM ubuntu:24.04

# Install basic dependencies and libraries needed for VS Code server
RUN apt-get update && apt-get install -y \
    curl \
    git \
    xz-utils \
    sudo \
    ca-certificates \
    libc6 \
    libstdc++6 \
    libnss3 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libxss1 \
    libasound2t64 \
    wget \
    gnupg \
    build-essential \
    libc6-dev \
    libstdc++-12-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for VS Code server)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - \
    && apt-get install -y nodejs

# Install Nix package manager
RUN curl -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

# Add Nix to PATH and enable flakes
ENV PATH="/nix/var/nix/profiles/default/bin:$PATH"
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Source nix environment and add nixpkgs channel
RUN . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && \
    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs && \
    nix-channel --update

# Install direnv using nix profile
RUN . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && \
    nix profile install nixpkgs#direnv

# Create workspace directory
RUN mkdir -p /workspace

# Set up workspace as working directory
WORKDIR /workspace

# Set up git config placeholder (will be overridden by user)
RUN git config --global user.name "devcontainer" && \
    git config --global user.email "devcontainer@example.com"

# Set default shell
SHELL ["/bin/bash", "-c"]

# Ensure Nix is available in shell sessions and set up direnv
RUN echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' >> /root/.bashrc && \
    echo 'eval "$(direnv hook bash)"' >> /root/.bashrc && \
    echo 'cd /workspace && direnv allow 2>/dev/null || true' >> /root/.bashrc
