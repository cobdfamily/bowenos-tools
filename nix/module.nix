{ config, lib, pkgs, ... }:

let
  cfg = config.services.bowenos-tools;
in {
  options.services.bowenos-tools = {
    enable = lib.mkEnableOption "BowenOS tooling CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bowenos-tools;
      defaultText = lib.literalExpression "pkgs.bowenos-tools";
      description = "BowenOS tools package to add to the system.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
