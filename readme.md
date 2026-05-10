# zmk-workspace

This repository is a workspace for building ZMK firmware, based on [urob's zmk-config](https://github.com/urob/zmk-config).

Difference from urob's zmk-config:
- zmk-config can also be in subdirectory of `config/` (while `config/` is still supported). This enables you to have multiple zmk-configs.
- Supports extra modules for zmk-config and tests
- Dev Container support
- keymap-drawer support
- Tab completion for `./just.sh build` and `./just.sh flash` with fzf
- `./just.sh flash` is added for UF2 loader (Only works on Windows(WSL) or macOS)
- Automatically removes `.west` before `just init`

## Usage

### Local build environment (WSL)

> [!important]
> On Windows, it is recommended that the workspace be located on WSL-native location (outside of `/mnt/c/`). Syncing the directory between Windows and WSL / container will result in significantly slower builds.

On WSL, you can edit files directly in the WSL workspace and run `./just.sh init`, `./just.sh build`, `./just.sh flash`, etc. from WSL. Build-related commands execute `just` and the ZMK toolchain inside Docker using `.devcontainer/Dockerfile`, while generated files remain owned by your WSL user.

Builds use `ccache` inside the container. The cache is stored at `.cache/ccache` on the WSL filesystem and is ignored by Git. You can inspect it with `./just.sh ccache-stats` and clear it with `./just.sh clean-ccache`. The default cache limit is 5 GiB; override it with `ZMK_WORKSPACE_CCACHE_MAXSIZE=10G ./just.sh build all`.

1. Clone this repo
1. See [VSCode Docs](https://code.visualstudio.com/docs/devcontainers/containers) for Dev Container usage. Or, see [urob's zmk-config README](https://github.com/urob/zmk-config#local-build-environment) for Nix and direnv setup
2. git clone your zmk-config into `config`
   ```sh
   cd config
   git clone https://github.com/your-username/zmk-config-your-keyboard
   cd ..
   ```
4. Init and select the target config
   ```sh
   ./just.sh init config/zmk-config-your-keyboard
   ```
   Or if you prefer to treat zmk-workspace as the root of your zmk-config,
   ```sh
   ./just.sh init config
   ```
   You can omit the config name to use fzf to select the config.
5. Build
   ```sh
   ./just.sh build [target]
   ```
6. Flash
   ```sh
   ./just.sh flash [target]
   ```
   or you can specify `-r` to build before flashing
   ```sh
   ./just.sh flash [target] -r
   ```
7. Draw keymap
   ```sh
   just draw
   ```
   Generated files are written to `keymap-drawer/<name>.yaml` and `keymap-drawer/<name>.svg` under the active ZMK config.

7. Draw keymap
   ```sh
   ./just.sh draw-keymap
   ```
   or draw a specific `config/*.keymap` basename
   ```sh
   ./just.sh draw-keymap myboard
   ```
   This also regenerates `config/<name>.json` from the ZMK physical layout before drawing.

## Tab completion

Enable completion in the current Bash session:

```sh
source ./_just_completion.bash
```

Then use `Tab` after `./just.sh`:

```sh
./just.sh <Tab>
./just.sh build <Tab>
./just.sh init <Tab>
```

To enable it automatically in Bash, add this to `~/.bashrc`:

```sh
source /path/to/zmk-workspace/_just_completion.bash
```

The completion works with `./just.sh` on WSL. If `fzf` is installed on the host, target/config selection uses an interactive picker; otherwise it falls back to normal Bash completion candidates.

With Dev Container or `nix develop`, tab completion is enabled by default via `postCreateCommand`.
