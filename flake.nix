{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, ... }: let
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  in {
    overlays.inputs = final: prev: { inherit inputs; };
  } // inputs.flake-utils.lib.eachSystem platforms (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = builtins.attrValues self.overlays;
      };
      inherit (nixpkgs) lib;
    in {
      devShell = pkgs.mkShell {
        name = "dotnet-aks-dhall";

        buildInputs = with pkgs; [
          dhall
          dhall-json
          jq
          git
          kubectl
        ];
      };
  });
}
