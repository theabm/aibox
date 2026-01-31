{
  description = "Agent sandbox base flake + templates";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
    {
      lib.mkSandboxSystem = import ./lib/mkSandboxSystem.nix {
        inherit nixpkgs;
      };

      templates.project = {
        path = ./templates/project;
        description = "NixOS VM agent sandbox project template";
      };
    };
}
