{
  description = "Reusable MicroVM sandbox builder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm, ... }:
    let
      lib = nixpkgs.lib;

      # Function that builds a microVM NixOS system for a given project + package list.
      mkSandboxSystem =
        { system
        , projectDir
        , authorizedKeys ? ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO4i3B/ShuuG5zvddLbazGYNEfat3C8TF7d5ixARpHUb andres@dede"]
        , packages ? []
        , hostPort ? 2222
        , vcpu ? 4
        , mem ? 4096
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            microvm.nixosModules.microvm
            ({ pkgs, ... }: {
              system.stateVersion = "25.11";
              networking.hostName = "agent-sandbox";

              environment.systemPackages =
                (with pkgs; [
                  fish
                  git
                  curl
                  ripgrep
                  fd
                  jq
                  tmux
                  neovim
                ]) ++ packages;

              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = false;
                  KbdInteractiveAuthentication = false;
                  PermitRootLogin = "no";
                };
                openFirewall = true;
              };

              # Networking: bring up the microVM NIC via DHCP
              networking.useNetworkd = true;
              systemd.network.enable = true;

              systemd.network.networks."10-ethernet" = {
                matchConfig.Name = "en* eth*";
                networkConfig.DHCP = "yes";
              };


              users.users.dev =
              let
                keys = if builtins.isList authorizedKeys then authorizedKeys else [ authorizedKeys ];
              in
              {
                isNormalUser = true;
                extraGroups = [ "wheel" ];
                openssh.authorizedKeys.keys = keys;
                shell = pkgs.fish;
                initialPassword = "dev";
              };


              security.sudo = {
                enable = true;
                wheelNeedsPassword = false;
              };

              programs.fish = {
                enable = true;
                interactiveShellInit = ''
                  cd /workspace
                '';
              };

              microvm = {
                hypervisor = "qemu";

                interfaces = [
                  {
                    type = "user";
                    id = "usernet";
                    mac = "02:00:00:00:00:01";
                  }
                ];

                forwardPorts = [
                  { from = "host"; host.port = hostPort; guest.port = 22; }
                ];

                inherit vcpu mem;

                shares = [
                  {
                    proto = "9p";
                    tag = "workspace";
                    source = projectDir;
                    mountPoint = "/workspace";
                  }
                ];

                volumes = [ ];
              };
            })
          ];
        };
    in
    {
      # Export the function so projects can call it.
      lib.mkSandboxSystem = mkSandboxSystem;
    };
}

