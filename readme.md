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

Two build environment options are available. Choose one:

- **Docker** — use `./just.sh <command>`. The script builds and runs commands inside Docker automatically.
- **Nix / direnv** — enter `nix develop` (or use direnv), then use `just <command>` directly. `./just.sh` is not needed.

For Dev Container usage, see [VSCode Docs](https://code.visualstudio.com/docs/devcontainers/containers).
For Nix and direnv setup, See [urob's zmk-config README](https://github.com/urob/zmk-config#local-build-environment).

> [!important]
> On Windows, it is recommended that the workspace be located on WSL-native location (outside of `/mnt/c/`). Syncing the directory between Windows and WSL / container will result in significantly slower builds.

1. Clone this repo
   ```sh
   git clone https://github.com/kot149/zmk-workspace.git
   cd zmk-workspace
   ```
2. git clone your zmk-config into `config`
   ```sh
   cd config
   git clone https://github.com/your-username/zmk-config-your-keyboard
   cd ..
   ```
3. Enter the Nix shell
   ```sh
   nix develop
   ```
   or
   ```sh
   direnv allow
   ```
4. Init and select the target config
   ```sh
   just init config/zmk-config-your-keyboard
   ```
5. Build
   ```sh
   just build [target]
   ```
6. Flash
   ```sh
   just flash [target]
   ```
7. Draw keymap
   ```sh
   just draw-keymap
   ```

## Tab completion

Enable completion in the current Bash session:

```sh
source ./_just_completion.bash
```

Then use `Tab` after `./just.sh`:

```sh
just <Tab>
just build <Tab>
just init <Tab>
```

To enable it automatically in Bash, add this to `~/.bashrc`:

```sh
source /path/to/zmk-workspace/_just_completion.bash
```

If `fzf` is installed on the host, target/config selection uses an interactive picker; otherwise it falls back to normal Bash completion candidates.
