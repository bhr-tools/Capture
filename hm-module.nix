self:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.capture;
  package = cfg.package.override { inherit (cfg) ocrLanguages; };
in {
  options.programs.capture = {
    enable = lib.mkEnableOption "screenshots, screen recording and on-screen text selection";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The capture package to use.";
    };

    ocrLanguages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "eng" "fra" ];
      description = "Tesseract languages used to read text, by order of preference.";
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the daemon with Hyprland (exec-once).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    wayland.windowManager.hyprland.settings.exec-once =
      lib.mkIf cfg.autostart [ "${lib.getExe package} daemon" ];
  };
}
