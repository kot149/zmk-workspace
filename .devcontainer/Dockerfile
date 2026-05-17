FROM zmkfirmware/zmk-build-arm:stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bsdmainutils \
        ccache \
        fzf \
        just \
        python3-venv \
        sudo \
        yq \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/keymap-drawer \
    && /opt/keymap-drawer/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/keymap-drawer/bin/pip install --no-cache-dir \
        keymap-drawer==0.21.0 \
        tree-sitter==0.24.0 \
        tree-sitter-devicetree==0.14.1 \
    && ln -s /opt/keymap-drawer/bin/keymap /usr/local/bin/keymap

RUN git config --system --add safe.directory '*'

ARG USERNAME=ubuntu
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN if ! id -u "${USERNAME}" >/dev/null 2>&1; then \
        if ! getent group "${USER_GID}" >/dev/null; then groupadd --gid "${USER_GID}" "${USERNAME}"; fi; \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" -m "${USERNAME}"; \
    fi \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" >/etc/sudoers.d/"${USERNAME}" \
    && chmod 0440 /etc/sudoers.d/"${USERNAME}"
