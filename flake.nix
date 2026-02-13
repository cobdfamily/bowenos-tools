{
  description = "BowenOS Installer and Recovery with nix + ssh + disko + zfs (serial friendly, with ttyS0 first)";

  inputs = {
    # Pin nixpkgs to something stable so ZFS is less likely to break.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }:
  let
    inherit (nixpkgs) lib;
    isoSystem = "x86_64-linux";
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f {
          inherit system;
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        });
  in {
    overlays.default = final: prev: {
      bowenos-tools = final.callPackage ./nix/package.nix { };
    };

    nixosConfigurations.bowenos-installer-recovery = nixpkgs.lib.nixosSystem {
      system = isoSystem;
      modules = [
        # Minimal installer ISO base
        ({ pkgs, lib, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];

          imports = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ];

          # Make the ISO nice to use over serial (Incus-friendly)
          boot.kernelParams = [
            "console=ttyS0,115200n8"
            "console=tty1"
          ];
          services.getty.autologinUser = lib.mkDefault "root";

          # Networking + SSH
          networking.useDHCP = lib.mkDefault true;
          services.openssh = {
            enable = true;
            settings = {
              PermitRootLogin = "yes";
              PasswordAuthentication = true;
            };
          };

          # Simple default creds for a BOOTSTRAP ISO (change if you care)
          users.users.root.initialPassword = "nixos";

          # Nix usability
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          nix.settings.sandbox = false; # makes life easier in live/rescue contexts

          environment.systemPackages = with pkgs; [
            bowenos-tools
            curl
            git
            tmux
            htop
            # disko (both the input and the package exist; package is simplest)
            disko.packages.${isoSystem}.default
            # ZFS userspace tools
            zfs
          ];

          # Try to ensure ZFS kernel module is available
          boot.supportedFilesystems = [ "zfs" ];
          boot.zfs.enableUnstable = false;

          # Pin a kernel series that commonly has ZFS wired up in nixpkgs.
          # If this line ever causes evaluation errors on your pin, swap to:
          #   boot.kernelPackages = pkgs.linuxPackages;
          boot.kernelPackages = pkgs.linuxPackages_6_6;

          # Helpful: tell ZFS userspace where to look
          environment.sessionVariables.ZPOOL_SCRIPTS_PATH = "${pkgs.zfs}/libexec/zfs";

          # Quality-of-life: show IP on login, etc. (optional)
          programs.bash.interactiveShellInit = ''
            echo
            echo "BowenOS Installer and Recovery ready."
            echo "IP addresses:"
            ip -brief addr || true
            echo
            echo "Try:"
            echo "  nix run github:nix-community/nixos-anywhere -- --help"
            echo "  disko --help"
            echo "  modprobe zfs && zpool status   (if module is present)"
            echo
          '';
        })

        # Make the disko module available if you want to import it later
        disko.nixosModules.disko
      ];
    };
    nixosConfigurations.bootstrap-iso = self.nixosConfigurations.bowenos-installer-recovery;

    packages = forAllSystems ({ system, pkgs }: {
      default = pkgs.bowenos-tools;
      bowenos-tools = pkgs.bowenos-tools;
    } // lib.optionalAttrs (system == isoSystem) {
      # Convenience output: `nix build .#iso`
      iso = self.nixosConfigurations.bowenos-installer-recovery.config.system.build.isoImage;
    });

    apps = forAllSystems ({ pkgs, ... }: {
      default = {
        type = "app";
        program = "${pkgs.bowenos-tools}/bin/bowenos";
      };
      bowenos = {
        type = "app";
        program = "${pkgs.bowenos-tools}/bin/bowenos";
      };
    });

    nixosModules.default = import ./nix/module.nix;
  };
}
