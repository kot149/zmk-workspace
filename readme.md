# zmk-workspace

This repository is a workspace for building ZMK firmware, based on [urob's zmk-config](https://github.com/urob/zmk-config).

Difference from urob's zmk-config:
- config is isolated per keyboard in `config/zmk-config-<keyboard>`
  - Specify which keyboard to build with `ZMK_CONFIG` environment variable e.g. `ZMK_CONFIG=zmk-config-roBa just build roBa`
- `just flash` is added to flash the firmware to the device from WSL (requires PowerShell 7 installed on the host machine)
- Automatically removes `.west` when `just init` is run
- Dev Container support
- ZMK, Zephyr, and zmk-configs are added as submodules

Note: keymap-drawer is not compatible with this setup.

## Usage

### Local build environment

1. See [urob's zmk-config README](https://github.com/urob/zmk-config#local-build-environment) for Nix and direnv setup, or use Dev Container
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
