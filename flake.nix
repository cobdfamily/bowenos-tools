{
  description = "Bootstrap ISO with nix + ssh + disko + zfs (serial friendly, with ttyS0 first)";

  inputs = {
    # Pin nixpkgs to something stable so ZFS is less likely to break.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }:
  let
    system = "x86_64-linux";
  in {
    nixosConfigurations.bootstrap-iso = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        # Minimal installer ISO base
        ({ pkgs, lib, ... }: {
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
            curl
            git
            tmux
            htop
            # disko (both the input and the package exist; package is simplest)
            disko.packages.${system}.default
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
            echo "Bootstrap ISO ready."
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

    # Convenience output: `nix build .#iso`
    packages.${system}.iso =
      self.nixosConfigurations.bootstrap-iso.config.system.build.isoImage;
  };
}
