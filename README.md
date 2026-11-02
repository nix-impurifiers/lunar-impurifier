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
