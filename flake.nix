{
  description = "Agent sandbox base flake + templates";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm, ... }:
    {
      lib.mkSandboxSystem = import ./lib/mkSandboxSystem.nix {
        inherit nixpkgs microvm;
      };

      templates.project = {
        path = ./templates/project;
        description = "MicroVM agent sandbox project template";
      };
    };
}

