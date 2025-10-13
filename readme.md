# zmk-workspace

This repository is a workspace for building ZMK firmware, based on [urob's zmk-config](https://github.com/urob/zmk-config).

Difference from urob's zmk-config:
- zmk-config can also be in subdirectory of `config/` (while `config/` is still supported). This enables you to have multiple zmk-configs.
- Supports extra modules for zmk-config and tests
- Dev Container support
- Tab completion for `just build` and `just flash` with fzf
- `just flash` is added for UF2 loader (Only works on WSL with Nix, and requires PowerShell installed on the host machine)
- Automatically removes `.west` before `just init`

> [!note]
> keymap-drawer is not compatible with this setup.

## Usage

### Local build environment

> [!important]
> When using Dev Container on Windows, it is recommended that the host directory also be located on WSL (and outside of `/mnt/c/`); syncing the directory between Windows and WSL (container) will result in significantly slower builds.

1. Install [mise](https://mise.jdx.dev)
   ```sh
   curl https://mise.run | sh
   ```
1. Clone this repo
2. git clone your zmk-config into `config`
   ```sh
   cd config
   git clone https://github.com/your-username/zmk-config-your-keyboard
   cd ..
   ```
3. Setup the environment
   ```sh
   mise setup
   ```
4. Init and select the target config
   ```sh
   mise init config/zmk-config-your-keyboard
   ```
   Or if you prefer to treat zmk-workspace as the root of your zmk-config,
   ```sh
   mise init config
   ```
   You can omit the config name to use fzf to select the config.
5. Build
   ```sh
   mise build [target]
   ```
6. Flash
   ```sh
   mise flash [target]
   ```
   or you can specify `-r` to build before flashing
   ```sh
   mise flash [target] -r
   ```

## Tab completion

With Dev Container or `nix develop` command, tab completion is enabled by default.

Otherwise, manually run `source _just_completion.bash` on Zsh to enable tab completion.
```sh
source _just_completion.bash
```
