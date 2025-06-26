# zmk-workspace

This repository is a workspace for building ZMK firmware, based on [urob's zmk-config](https://github.com/urob/zmk-config).

Difference from urob's zmk-config:
- zmk-config is isolated per keyboard in `config/zmk-config-<keyboard>`
- Dev Container support
- `just flash` is added to for UF2 loader (Only works on WSL with Nix, and requires PowerShell 7 installed on the host machine)
- Automatically removes `.west` when `just init` is run
- ZMK, Zephyr, and zmk-configs are added as submodules

> [!note]
> keymap-drawer is not compatible with this setup.

## Usage

### Local build environment

> [!important]
> When using Dev Container on Windows, it is recommended that the host directory also be located in the WSL; synchronizing the directory between Windows and the WSL (container) will result in significantly slower builds.

1. See [urob's zmk-config README](https://github.com/urob/zmk-config#local-build-environment) for Nix and direnv setup, or Use Dev Container
2. git clone your ZMK config into `config`
   ```sh
   git clone https://github.com/your-username/zmk-config-your-keyboard config/zmk-config-your-keyboard
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
