FROM zmkfirmware/zmk-build-arm:stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends just yq bsdmainutils fzf python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/keymap-drawer \
    && /opt/keymap-drawer/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/keymap-drawer/bin/pip install --no-cache-dir \
        keymap-drawer==0.21.0 \
        tree-sitter==0.24.0 \
        tree-sitter-devicetree==0.14.1 \
    && ln -s /opt/keymap-drawer/bin/keymap /usr/local/bin/keymap

RUN git config --global --add safe.directory '*'

RUN echo 'source /zmk-workspace/_just_completion.bash' >> /root/.bashrc
