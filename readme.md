# zmk-workspace

This repository is a workspace for building ZMK firmware, based on [urob's zmk-config](https://github.com/urob/zmk-config).

Difference from urob's zmk-config:
- zmk-config can also be in subdirectory of `config/` (while `config/` is still supported). This enables you to have multiple zmk-configs.
- Supports extra modules for zmk-config and tests
- Dev Container support
- Tab completion for `just build` and `just flash` with fzf
- `just flash` is added for UF2 loader (Only works on Winodws(WSL) or macOS with Nix)
- Automatically removes `.west` before `just init`

> [!note]
> keymap-drawer is not compatible with this setup.

## Usage

### Local build environment

> [!important]
> On Windows, it is recommended that the workspace be located on WSL-native location (outside of `/mnt/c/`). Syncing the directory between Windows and WSL / container will result in significantly slower builds.

1. Clone this repo
1. See [VSCode Docs](https://code.visualstudio.com/docs/devcontainers/containers) for Dev Conainer usage. Or, see [urob's zmk-config README](https://github.com/urob/zmk-config#local-build-environment) for Nix and direnv setup
2. git clone your zmk-config into `config`
   ```sh
   cd config
   git clone https://github.com/your-username/zmk-config-your-keyboard
   cd ..
   ```
4. Init and select the target config
   ```sh
   just init config/zmk-config-your-keyboard
   ```
   Or if you prefer to treat zmk-workspace as the root of your zmk-config,
   ```sh
   just init config
   ```
   You can omit the config name to use fzf to select the config.
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

## Tab completion

With Dev Container or `nix develop` command, tab completion is enabled by default.

Otherwise, manually run `source _just_completion.bash` on Zsh to enable tab completion.
```sh
source _just_completion.bash
```
