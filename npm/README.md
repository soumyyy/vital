# vital-mac

Installer and command line for [Vital](https://github.com/soumyyy/vital), a lean menu bar monitor for macOS on Apple silicon: CPU, memory, storage, heat and fans, with safe Quit and Force Quit.

```sh
npx vital-mac install
```

This downloads the latest notarized release from GitHub, checks its SHA-256 against the published `SHA256SUMS`, verifies the signature, installs `Vital.app` into `/Applications` and opens it. Adding the package runs no install script; nothing is downloaded until you run `install`.

```sh
npm install -g vital-mac     # also puts the `vital` command on your PATH
vital status                 # CPU, memory, storage, heat, fans, network, battery
vital apps --by memory -n 5  # apps ranked by one vital, helpers included
vital history cpu --range 6h # from the 24 hour record
vital status --json          # stable JSON for scripts and AI agents
```

`vital-mac uninstall` removes the app and its fan helper. Full command reference: [docs/CLI.md](https://github.com/soumyyy/vital/blob/main/docs/CLI.md).

Requires macOS 14 or later on Apple silicon and Node 18 or later. MIT licensed.
