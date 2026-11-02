# Testing

Run `nix flake check -L`. The QEMU fixture uses upstream native Lunar scripts and
actual installwatch. Assert native file inventories, installed state and program
behavior. Cover native checksums/license policy, failures/retry, runtime gates,
accounts/permissions, host-library updates, GC, configuration and foreign roots.
Do not replace native transactions with mock package-manager commands.
