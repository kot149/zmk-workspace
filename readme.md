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
> On Windows, you are required to use WSL and it is recommended that the directory be located outside of `/mnt/c/`; syncing the directory between Windows and WSL will result in significantly slower builds.

1. Install [mise](https://mise.jdx.dev)
   ```sh
   curl https://mise.run | sh
   ```
1. Clone this repo (use `--recursive` to also clone submodules)
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
2. Setup
   ```sh
   mise setup
   ```
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
