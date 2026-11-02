# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "lunar-impurifier";
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
  };
  valid = name: builtins.match "[a-z0-9][a-z0-9+._-]*" name != null;
  buildModule =
    {
      name,
      version,
      payload,
      dependencies ? [ ],
      activate ? false,
      licenses ? [ "MIT" ],
      nativeLicense ? lib.head licenses,
      description ? "Nix projected application",
    }:
    assert lib.assertMsg (
      valid name && valid version && lib.all valid dependencies
    ) "invalid module identity or dependency";
    let
      archive = "${name}-${version}-${builtins.substring 0 32 (builtins.baseNameOf payload)}.tar.gz";
      details = pkgs.writeText "module-details" ''
        MODULE=${lib.escapeShellArg name}
        VERSION=${lib.escapeShellArg version}
        SOURCE=${lib.escapeShellArg archive}
        SOURCE_URL_FULL[0]="file://$SCRIPT_DIRECTORY/$SOURCE"
        SOURCE_DIRECTORY="$BUILD_DIRECTORY/$MODULE-$VERSION"
        SOURCE_VFY=sha256:PAYLOAD_HASH
        ENTERED=20261102
        UPDATED=20261102
        LICENSE=${lib.escapeShellArg nativeLicense}
        IMPURIFIER_LICENSES=${lib.escapeShellArg (builtins.toJSON licenses)}
        SHORT=${lib.escapeShellArg description}
        printf '%s\n' ${lib.escapeShellArg description}
      '';
      phase = pkgs.writeText "module-phase" ''
        # SPDX-License-Identifier: MIT
        if [[ -x /usr/sbin/lunar-impurifier-activate ]]; then
          /usr/sbin/lunar-impurifier-activate
        fi
      '';
    in
    pkgs.runCommand "${name}-${version}-module"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = { inherit name version; };
      }
      ''
        mkdir -p root/${name}-${version}/root $out/${name}
        cp ${../LICENSE} $out/${name}/LICENSE
        cp -r ${payload}/. root/${name}-${version}/root/
        chmod -R u+w root
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -C root -cf - ${name}-${version} | gzip -n > $out/${name}/${archive}
        hash=$(sha256sum $out/${name}/${archive} | cut -d' ' -f1)
        sed "s/PAYLOAD_HASH/$hash/" ${details} > $out/${name}/DETAILS
        printf '%s\n' 'default_pre_build' > $out/${name}/PRE_BUILD
        cat > $out/${name}/BUILD <<'BUILD'
        [[ ''${ROOT:-/} == / && ''${DESTDIR:-/} == / ]] || { message 'Impurifier modules require the live host root'; return 1; }
        [[ -r /usr/lib/installwatch.so ]] || { message 'Native installwatch is required'; return 1; }
        prepare_install &&
        # Bridge Lunar's legacy variable to current native installwatch.
        export INSTW_LOGFILE="$INSTALLWATCHFILE" &&
        cp -a "$SOURCE_DIRECTORY/root/." /
        BUILD
        ${lib.optionalString activate ''
          cp ${phase} $out/${name}/POST_INSTALL
          cp ${phase} $out/${name}/POST_REMOVE
        ''}
        ${lib.optionalString (dependencies != [ ]) ''
          printf '%s\n' ${
            lib.concatMapStringsSep " " (d: lib.escapeShellArg "depends ${d}") dependencies
          } > $out/${name}/DEPENDS
        ''}
        chmod 755 $out/${name}/{DETAILS,PRE_BUILD,BUILD}
        find $out/${name} -maxdepth 1 -type f ! -name '*.tar.gz' -exec chmod 755 {} +
      '';
  makeRuntimeModule =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
      installwatchDependency ? "installwatch",
      version ? core.runtimeVersion,
    }:
    buildModule {
      name = "lunar-impurifier";
      inherit version;
      dependencies = [
        nixDependency
        pythonDependency
        installwatchDependency
      ];
      activate = true;
      payload = pkgs.runCommand "lunar-runtime" { } ''
        cp -r ${core.makeRuntimeTree { }} $out
        chmod -R u+w $out
        install -Dm755 ${../src/activate.py} $out/usr/sbin/lunar-impurifier-activate
        install -Dm755 ${../src/nix_impurifier.plugin} $out/var/lib/lunar/plugins/nix_impurifier.plugin
        install -Dm755 ${../src/adapter.py} $out/usr/sbin/lunar-impurifier
        mkdir -p $out/usr/share/lunar-impurifier
        echo '${version}' > $out/usr/share/lunar-impurifier/runtime-version
      '';
    };
  makeModule =
    args@{
      pkg,
      hostDependencies ? [ ],
      nativeLicense ? null,
      ...
    }:
    assert lib.assertMsg (
      (args.systemd or null) == null && (args.openrc or null) == null && (args.runit or null) == null
    ) "Lunar service startup remains native host policy; no systemd/OpenRC/runit backend is assumed";
    let
      application = core.makePayload (
        (builtins.removeAttrs args [
          "hostDependencies"
          "nativeLicense"
        ])
        // {
          hostBackend = "openrc";
        }
      );
      payload = pkgs.runCommand "lunar-application" { } ''
        cp -r ${application} $out
        chmod -R u+w $out
        mkdir -p $out/usr/share/lunar-impurifier/requirements
        echo '${core.runtimeVersion}' > $out/usr/share/lunar-impurifier/requirements/${application.name}
      '';
    in
    buildModule {
      name = application.name;
      version = "${application.version}-${if application.offline then "offline" else "net"}";
      inherit payload;
      inherit (application) description;
      licenses = [
        "MIT"
      ]
      ++ map (license: if builtins.isAttrs license then license.spdxId or "UNKNOWN" else "UNKNOWN") (
        lib.toList (pkg.meta.license or [ ])
      );
      nativeLicense =
        if nativeLicense != null then
          nativeLicense
        else
          let
            values = lib.toList (pkg.meta.license or [ ]);
          in
          if values == [ ] || !(builtins.isAttrs (lib.head values)) then
            "LicenseRef-Unknown"
          else
            (lib.head values).spdxId or "LicenseRef-Unknown";
      dependencies = [ "lunar-impurifier" ] ++ hostDependencies;
      activate = true;
    };
  makeMoonbase =
    {
      modules,
      name ? "impurifiers",
    }:
    assert lib.assertMsg (
      lib.length (lib.unique (map (s: s.name) modules)) == lib.length modules
    ) "one selected module per logical package";
    pkgs.runCommand "${name}-moonbase"
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        mkdir -p $out/impurifiers $out/source-cache
        cp ${../LICENSE} $out/LICENSE
        ${lib.concatMapStringsSep "\n" (s: "cp -r ${s}/. $out/impurifiers/") modules}
        for archive in $out/impurifiers/*/*.tar.gz; do
          ln -s "../''${archive#"$out/"}" "$out/source-cache/''${archive##*/}"
        done
        mkdir -p $out/zlocal
        touch $out/aliases
      '';
in
{
  inherit
    buildModule
    makeModule
    makeRuntimeModule
    makeMoonbase
    ;
  makeNetModule = args: makeModule (args // { offline = false; });
  makeOfflineModule = args: makeModule (args // { offline = true; });
  makePackage = args: {
    net = makeModule (args // { offline = false; });
    offline = makeModule (args // { offline = true; });
  };
  runtimeModule = makeRuntimeModule { };
  inherit (core) unit;
}
