# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
  bundled ? false,
}:
let
  nativeProof = pkgs.pkgsStatic.stdenv.mkDerivation {
    name = "native-static-proof";
    dontUnpack = true;
    buildPhase = ''
      cat > proof.c <<'C'
      #include <stdio.h>
      int main(void) { puts("Hello from native payload"); return 0; }
      C
      $CC proof.c -o proof
    '';
    installPhase = "mkdir -p $out/bin; cp proof $out/bin/";
  };
  source = import ../nix/tools.nix { inherit pkgs; };
  module = pkgs.runCommand "native-lunar-fixture" { } ''
    mkdir -p $out/test/native-marker
    cat > $out/test/native-marker/DETAILS <<'MODULE'
    MODULE=native-marker
    VERSION=1
    LICENSE=MIT
    SOURCE_DIRECTORY=$BUILD_DIRECTORY/$MODULE-$VERSION
    ENTERED=20261102
    UPDATED=20261102
    SHORT="Native ownership fixture"
    cat << EOT
    Native Lunar fixture.
    EOT
    MODULE
    cat > $out/test/native-marker/PRE_BUILD <<'MODULE'
    mkdir -p "$SOURCE_DIRECTORY"
    MODULE
    cat > $out/test/native-marker/BUILD <<'MODULE'
    echo native > "$SOURCE_DIRECTORY/marker"
    prepare_install &&
    export INSTW_LOGFILE="$INSTALLWATCHFILE" &&
    install -Dm644 "$SOURCE_DIRECTORY/marker" /usr/share/lunar-vm/marker
    MODULE
    echo 'echo installed > /var/lunar-install-marker' > $out/test/native-marker/POST_INSTALL
    echo 'echo removed > /var/lunar-remove-marker' > $out/test/native-marker/POST_REMOVE
  '';
  tool =
    version:
    pkgs.runCommand "lunar-tool-${version}"
      {
        meta.license = pkgs.lib.licenses.mit;
        pname = "lunar-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/lunar-tool
        chmod 755 $out/bin/lunar-tool
      '';
  app =
    offline: version:
    impurifier.makeModule {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/lunar-app.conf" = pkgs.writeText "lunar-app.conf" "version=${version}\n";
      users.lunar-worker = { };
      directories."/var/lib/lunar-worker" = {
        owner = "lunar-worker:lunar-worker";
        mode = "0750";
      };
      lifecycle = {
        onInstall = "test -x /opt/nix/profile/bin/lunar-tool; echo initialized > /var/lib/lunar-worker/initialized";
        onUpgrade = "test ! -e /var/lib/lunar-worker/fail; echo ${version} > /var/lib/lunar-worker/migrated";
      };
    };
  provider =
    name:
    impurifier.buildModule {
      inherit name;
      version = "1";
      payload =
        pkgs.runCommand "${name}-vm-provider" { }
          "mkdir -p $out/usr/share/impurifier-vm; echo preinstalled > $out/usr/share/impurifier-vm/${name}";
    };
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  driver =
    version:
    impurifier.buildModule {
      name = "host-driver";
      inherit version;
      payload = fixture.driver version;
    };
  hardware = impurifier.makeOfflineModule {
    pkg = fixture.tool // {
      meta.license = pkgs.lib.licenses.mit;
    };
    inherit (fixture) hardware;
    hostDependencies = [ "host-driver" ];
  };
  denied = impurifier.buildModule {
    name = "license-rejected";
    version = "1";
    nativeLicense = "LicenseRef-ImpurifierTest";
    payload =
      pkgs.runCommand "license-rejected-fixture" { }
        "mkdir -p $out/usr/share/impurifier-vm; echo should-not-install > $out/usr/share/impurifier-vm/license-rejected";
  };
  nativeMoonbase =
    version:
    impurifier.makeMoonbase {
      modules = [
        (impurifier.makeNativeModule {
          name = "native-payload";
          inherit version;
          payload = pkgs.runCommand "native-lunar-${version}" { } ''
            mkdir -p $out/usr/libexec/native-lunar $out/usr/share
            cp ${nativeProof}/bin/proof $out/usr/libexec/native-lunar/proof
            echo ${version} > $out/usr/share/native-lunar-version
          '';
        })
      ];
    };
  moonbase =
    {
      offline,
      version,
      driverVersion ? "1",
      runtime ? impurifier.runtimeModule,
    }:
    impurifier.makeMoonbase {
      modules = [
        (provider "nix")
        (provider "python3")
        (provider "installwatch")
        runtime
        (app offline version)
        (driver driverVersion)
        hardware
        denied
      ];
    };
in
{
  native-vm = pkgs.testers.runNixOSTest {
    name = "lunar-native-contract";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.memorySize = 2048;
      virtualisation.useNixStoreImage = true;
      virtualisation.writableStore = true;
      nix.settings.substituters = lib.mkForce [ ];
      systemd.tmpfiles.rules = [
        "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
        "L+ /usr/bin/nix-store - - - - ${
          if bundled then
            pkgs.writeShellScript "incompatible-nix-store" "echo incompatible; exit 1"
          else
            "${pkgs.nix}/bin/nix-store"
        }"
        "L+ /usr/bin/nix - - - - ${pkgs.nix}/bin/nix"
      ];
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      environment.systemPackages = [
        pkgs.nix
        pkgs.python3
        pkgs.shadow
        pkgs.bash
        pkgs.gnumake
        pkgs.checkinstall
        pkgs.gawk
        pkgs.gnutar
        pkgs.gzip
        pkgs.bzip2
        pkgs.xz
        pkgs.file
        pkgs.procps
        pkgs.which
        pkgs.perl
        pkgs.patch
        pkgs.diffutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.util-linux
        pkgs.gettext
        pkgs.binutils
        pkgs.dialog
        pkgs.wget
        pkgs.glibc.bin
      ];
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      def succeed(command):
          return machine.succeed("export PATH=/sbin:/usr/sbin:/usr/bin:$PATH; " + command)
      succeed("mkdir -p /sbin /usr/bin /usr/sbin /usr/lib /usr/src /var/lock; for p in /run/current-system/sw/bin/* /run/current-system/sw/sbin/*; do test -e /usr/bin/$(basename $p) || ln -s $p /usr/bin/; done; ln -s ${pkgs.bash}/bin/bash /bin/bash")
      succeed("cp -r ${source} /root/lunar-source; cd /root/lunar-source; make install > /tmp/native-install.log 2>&1 || { cat /tmp/native-install.log; exit 1; }")
      succeed("cp ${pkgs.checkinstall}/lib/installwatch.so /usr/lib/installwatch.so; cp ${source}/LICENSE /usr/share/doc/lunar/LICENSE; touch /var/state/lunar/packages /var/state/lunar/depends")
      succeed("printf 'ACCEPTED_LICENSES=MIT\\nMOONBASE=/moonbase\\nPROMPT_DELAY=0\\nARCHIVE=off\\nCOLOR=off\\nCHECK_FREE_SPACE=off\\nUSE_WRAPPERS=no\\n' > /etc/lunar/local/config; cp -r ${module} /moonbase")
      succeed("lin -c native-marker > /tmp/lin.log 2>&1 || { cat /tmp/lin.log; exit 1; }")
      succeed("cat /var/log/lunar/install/native-marker-1; grep native /usr/share/lunar-vm/marker; grep installed /var/lunar-install-marker; grep native-marker /var/state/lunar/packages")
      succeed("! grep -E '^/nix/store/|^/usr/bin/|^/bin/' /var/log/lunar/install/native-marker-1 || { cat /var/log/lunar/install/native-marker-1; exit 1; }")
      succeed("lrm native-marker > /tmp/lrm.log 2>&1 || { cat /tmp/lrm.log; exit 1; }")
      succeed("test ! -e /usr/share/lunar-vm/marker; grep removed /var/lunar-remove-marker")
      def select_moonbase(path):
          succeed(f"rm -rf /moonbase; cp -r {path} /moonbase; chmod -R u+w /moonbase; rm -f /var/state/lunar/module.index")
      def fail(command):
          return machine.fail("export PATH=/sbin:/usr/sbin:/usr/bin:$PATH; " + command)
      with subtest("native generated modules without engine activation"):
          for version, path in [(1, "${nativeMoonbase "1"}"), (2, "${nativeMoonbase "2"}")]:
              select_moonbase(path)
              succeed("lin -c --from /moonbase/source-cache native-payload > /tmp/native-payload.log 2>&1; grep '^" + str(version) + "$' /usr/share/native-lunar-version || { cat /tmp/native-payload.log; exit 1; }")
              succeed("grep /usr/libexec/native-lunar/proof /var/log/lunar/install/native-payload-" + str(version))
          succeed("mkdir -p /srv/native; cp /usr/libexec/native-lunar/proof /srv/native/proof; chroot /srv/native /proof | grep Hello; test ! -e /srv/native/nix; test ! -e /usr/sbin/lunar-impurifier-activate")
          succeed("lrm native-payload; test ! -e /usr/libexec/native-lunar/proof; test ! -e /usr/share/native-lunar-version")
      select_moonbase("${
        moonbase {
          offline = false;
          version = "1";
        }
      }")
      succeed("lin -c --from /moonbase/source-cache lunar-impurifier > /tmp/runtime.log 2>&1; test -x /usr/sbin/lunar-impurifier || { cat /tmp/runtime.log; exit 1; }")
      succeed("test ! -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
      fail("lunar-impurifier install --from /moonbase/source-cache lunar-tool > /tmp/net.log 2>&1")
      select_moonbase("${
        moonbase {
          offline = true;
          version = "1";
        }
      }")
      succeed("lunar-impurifier install --from /moonbase/source-cache lunar-tool > /tmp/offline.log 2>&1 || { cat /tmp/offline.log; exit 1; }")
      succeed("test $(/opt/nix/profile/bin/lunar-tool) = 1; id lunar-worker; test $(stat -c %a /var/lib/lunar-worker) = 750; grep initialized /var/lib/lunar-worker/initialized")
      succeed("echo customized > /etc/lunar-app.conf")
      select_moonbase("${
        moonbase {
          offline = true;
          version = "2";
        }
      }")
      succeed("touch /var/lib/lunar-worker/fail")
      fail("lunar-impurifier install --from /moonbase/source-cache lunar-tool > /tmp/failed-upgrade.log 2>&1")
      succeed("rm /var/lib/lunar-worker/fail; lunar-impurifier reconcile; test $(/opt/nix/profile/bin/lunar-tool) = 2; grep 2 /var/lib/lunar-worker/migrated")
      succeed("grep version=2 /etc/lunar-app.conf; echo modified > /etc/lunar-app.conf; ! grep -E '^/nix/store/|^/usr/bin/|^/bin/' /var/log/lunar/install/lunar-tool-2-offline")
      succeed("lunar-impurifier install --from /moonbase/source-cache hardware-tool > /tmp/hardware.log 2>&1 || { cat /tmp/hardware.log; exit 1; }; test $(/opt/nix/profile/bin/hardware-tool) = 1")
      select_moonbase("${
        moonbase {
          offline = true;
          version = "2";
          driverVersion = "2";
        }
      }")
      succeed("lin -c --from /moonbase/source-cache host-driver > /tmp/driver.log 2>&1; test $(/opt/nix/profile/bin/hardware-tool) = 2 || { cat /tmp/driver.log; exit 1; }")
      select_moonbase("${
        moonbase {
          offline = true;
          version = "2";
          driverVersion = "2";
          runtime = impurifier.makeRuntimeModule { version = "0.1"; };
        }
      }")
      fail("lunar-impurifier install --from /moonbase/source-cache lunar-impurifier > /tmp/runtime-old.log 2>&1")
      succeed("test $(/opt/nix/profile/bin/lunar-tool) = 2")
      select_moonbase("${
        moonbase {
          offline = true;
          version = "2";
          driverVersion = "2";
        }
      }")
      succeed("lunar-impurifier install --from /moonbase/source-cache lunar-impurifier > /tmp/runtime-current.log 2>&1 || { cat /tmp/runtime-current.log; exit 1; }")
      succeed("lin -c python3 > /tmp/native-source-url.log 2>&1 || { cat /tmp/native-source-url.log; exit 1; }")
      fail("lunar-impurifier install --from /moonbase/source-cache license-rejected > /tmp/denied.log 2>&1")
      succeed("grep 'LicenseRef-ImpurifierTest' /tmp/denied.log; test ! -e /usr/share/impurifier-vm/license-rejected")
      fail("ROOT=/foreign lin -c --from /moonbase/source-cache lunar-tool > /tmp/foreign.log 2>&1")
      succeed("test $(/opt/nix/profile/bin/lunar-tool) = 2")
      succeed("for file in /moonbase/impurifiers/lunar-tool/*.tar.gz; do cp \"$file\" \"$file.saved\"; printf corrupted >> \"$file\"; done")
      fail("lunar-impurifier install --from /moonbase/source-cache lunar-tool > /tmp/corrupt.log 2>&1")
      succeed("grep 'sha256sum check failed' /tmp/corrupt.log; test $(/opt/nix/profile/bin/lunar-tool) = 2")
      succeed("for file in /moonbase/impurifiers/lunar-tool/*.saved; do mv \"$file\" \"''${file%.saved}\"; done")
      succeed("nix-collect-garbage; test $(/opt/nix/profile/bin/lunar-tool) = 2; test $(/opt/nix/profile/bin/hardware-tool) = 2")
      fail("ROOT=/foreign lunar-impurifier reconcile")
      succeed("lunar-impurifier remove hardware-tool host-driver > /tmp/remove-hardware.log 2>&1 || { cat /tmp/remove-hardware.log; exit 1; }")
      succeed("lunar-impurifier remove lunar-tool > /tmp/remove-app.log 2>&1 || { cat /tmp/remove-app.log; exit 1; }")
      succeed("test ! -e /opt/nix/profile/bin/lunar-tool; test -f /var/lib/lunar-worker/initialized; grep modified /etc/lunar-app.conf")
    '';
  };
}
