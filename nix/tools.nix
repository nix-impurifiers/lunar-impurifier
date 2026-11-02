# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.fetchFromGitHub {
  owner = "lunar-linux";
  repo = "lunar";
  rev = "a011820d4588f64dcb249b7ea025d9e7e0db1593";
  hash = "sha256-Cztgrk15YLXqa0uVHVX0AtB6aCxSnLDEjFO1Y96WvLg=";
}
