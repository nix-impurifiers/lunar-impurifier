# lunar-impurifier

Build native Lunar modules and moonbases backed by transactional Nix profiles.
Actual `lin`, dependency resolution, installwatch and `lrm` own host files; Nix
owns application closures and garbage-collection roots. Original code is MIT.
See THIRD_PARTY.md for the independently licensed native tools used in tests.

```nix
let
  lunar = inputs.lunar-impurifier.lib.lunar-impurifier { inherit pkgs; };
in lunar.makeMoonbase {
  modules = [
    (lunar.makeRuntimeModule {
      nixDependency = "my-nix-provider";
      pythonDependency = "python3";
      installwatchDependency = "installwatch";
    })
    (lunar.makeOfflineModule {
      pkg = pkgs.hello;
      nativeLicense = "gpl";
    })
  ];
}
```

Select the emitted directory with Lunar's normal `MOONBASE` configuration. It
contains an `impurifiers` section, bundled source archives and a `source-cache`
directory. Supply the runtime's native dependency providers in your moonbase.
With Nix, Python and native installwatch already installed:

```
lin -c --from /srv/impurifiers/source-cache lunar-impurifier
lunar-impurifier install --from /srv/impurifiers/source-cache hello
lunar-impurifier reconcile
lunar-impurifier remove hello
```

`makeNetModule` emits a small installable Nix reference; `makeOfflineModule`
embeds its NAR cache. Native module names stay stable, with a `-net`/`-offline`
native version suffix. `makeMoonbase` rejects duplicate logical module names.
Source filenames distinguish payload revisions and native SHA-256 verification
remains enabled. The whole moonbase can be copied to another host; source URLs
refer to the selected module directory, not a build-machine store path.

The emitted BUILD runs native `prepare_install`, then copies its tracked payload.
It bridges Lunar's `INSTALLWATCHFILE` variable to current installwatch's
`INSTW_LOGFILE`. Missing native installwatch fails before installation. Native
`POST_INSTALL`/`POST_REMOVE` and a native plugin reconcile the profile, including
ordinary native host-library upgrades. Lunar's own `lrm --upgrade` suppresses
removal callbacks during replacement, preserving Nix upgrade/lifecycle state.

Native Lunar may hide errors from module callbacks. The adapter checks native
activity records and removal state, reconciles after the transaction, and returns
activation failures. Fix a failed lifecycle hook or missing closure and run
`reconcile`. Native package repair still uses Lunar. ROOT/DESTDIR mutations are
rejected by the adapter and generated build/activation helpers.

Native ownership policies apply. The VM verifies that ordinary payload upgrades
overwrite edited configuration, while native `PRESERVE=on` retains an edited file
on removal. Accounts and declared data directories survive removal. Service
declarations are rejected until native init integration is implemented; no
systemd, OpenRC or runit host is assumed.

Lunar accepts one native license token. `nativeLicense` defaults to the
application's primary SPDX identifier, or `LicenseRef-Unknown` without metadata;
set it to the appropriate native token when needed. The runtime's token is MIT.
Configure native `ACCEPTED_LICENSES`/`REJECTED_LICENSES` yourself: the adapter does
not relax that policy. Additional declared license identifiers are retained in
`IMPURIFIER_LICENSES` metadata; source and payload notices retain their licenses.

`buildModule` emits arbitrary native payloads and dependencies, allowing an
independent impure Nix provider package. Building a new native Nix installer is
deferred work, not excluded from the project.

Run `nix flake check -L` for the actual QEMU native client suite and `nix fmt`
for formatting. The fixture runs upstream Lunar scripts unmodified with a real
current installwatch library. It does not establish full Lunar boot/init or
historical installwatch coverage.

## Native payloads and bundled clients

`makeNativeModule { name; version; payload; dependencies?; ... }` emits a native
recipe from a producer-prepared tree, with engine activation disabled and no
implicit Nix dependency. Ordinary lin/lrm owns installation and removal using
real installwatch. The producer prepares a runnable target layout; this does not
relocate binaries. The VM installs two generated native versions before the
engine, checks native inventories and removal, and executes the installed static
payload in an isolated root without `/nix`. The manager fixture itself uses
NixOS host tools; this does not claim a complete target-distro boot without Nix.

`makeRuntimeModule` optionally accepts `bundledNixStore` and
`bundledNixNotices` for a static ELF client and upstream notices. Bundling omits
the default Nix dependency; Python and the native file tracker remain required.
Compatible external clients take precedence, explicit `IMPURIFIER_NIX_STORE`
disables fallback, and failed mutations are never retried through another
client. A bundled variant repeats the original lifecycle suite with an
incompatible external candidate. Nix provisioning remains deferred.
