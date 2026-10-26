{
  description = "Screenshots, screen recording and on-screen text selection for Hyprland, built on QuickShell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      packages = forAllSystems (pkgs: rec {
        capture = pkgs.callPackage ./package.nix { };
        default = capture;
      });

      homeManagerModules.default = import ./hm-module.nix self;

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ quickshell grim imagemagick tesseract zbar wf-recorder wl-clipboard jq ];
        };
      });
    };
}
