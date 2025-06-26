# zmk-workspace

This repository is a workspace for building ZMK firmware, based on [urob's zmk-config](https://github.com/urob/zmk-config).

Difference from urob's zmk-config:
- zmk-config is isolated per keyboard in `config/zmk-config-<keyboard>` and added as submodules
- Supports zmk-config which is also a module
- Dev Container support
- `just flash` is added for UF2 loader (Only works on WSL with Nix, and requires PowerShell 7 installed on the host machine)
- Automatically removes `.west` before `just init`

> [!note]
> keymap-drawer is not compatible with this setup.

## Usage

### Local build environment

> [!important]
> When using Dev Container on Windows, it is recommended that the host directory also be located on WSL (and outside of `/mnt/c/`); syncing the directory between Windows and WSL (container) will result in significantly slower builds.

1. Clone this repo (use `--recursive` to also clone submodules)
1. See [VSCode Docs](https://code.visualstudio.com/docs/devcontainers/containers) for Dev Conainer usage. Or, see [urob's zmk-config README](https://github.com/urob/zmk-config#local-build-environment) for Nix and direnv setup
2. git clone your zmk-config into `config`
   ```sh
   cd config
   git clone https://github.com/your-username/zmk-config-your-keyboard
   cd ..
   ```
3. Set `ZMK_CONFIG` environment variable
   ```sh
   export ZMK_CONFIG=zmk-config-your-keyboard
   ```
4. Init
   ```sh
   just init
   ```
5. Build
   ```sh
   just build [target]
   ```
6. Flash
   ```sh
   just flash [target]
   ```
   or you can specify `-r` to build before flashing
   ```sh
   just flash [target] -r
   ```
