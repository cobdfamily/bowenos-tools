# bowenos-tools

Run the tool help for command usage:

```bash
bowenos help
```

If you do not have `bowenos` installed locally, run it with Nix:

```bash
nix run github:cobdfamily/bowenos-tools -- help
```

Install the CLI into your profile:

```bash
nix profile install github:cobdfamily/bowenos-tools
```

NixOS module (adds `bowenos` to `environment.systemPackages`):

```nix
{
  imports = [ inputs.bowenos-tools.nixosModules.default ];
  services.bowenos-tools.enable = true;
}
```

The source of truth for installation workflow and system setup is:
`https://github.com/cobdfamily/bowenos`
