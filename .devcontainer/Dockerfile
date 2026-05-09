FROM zmkfirmware/zmk-build-arm:stable

RUN apt-get update && apt-get install -y just yq bsdmainutils fzf && rm -rf /var/lib/apt/lists/*

RUN git config --global --add safe.directory '*'

RUN echo 'source /zmk-workspace/_just_completion.bash' >> /root/.bashrc
