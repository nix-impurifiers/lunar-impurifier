# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }: {
  flake.lib = lib.mkForce {
    lunar-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
    in
    {
      formatter = pkgs.nixfmt-tree;
      packages.default = impurifier.runtimeModule;
      checks = import ../../../tests {
        inherit pkgs impurifier;
        coreSrc = inputs.impurifier;
      };
    };
}
