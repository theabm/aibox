{nixpkgs, microvm, ... }:
    let
      # Function that builds a microVM NixOS system for a given project + package list.
      mkSandboxSystem =
        { system
        , projectDir
        , authorizedKeys 
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

              # list any "basic" utilities here
              environment.systemPackages =
                (with pkgs; [
                  # I use fish shell
                  fish
                  git
                  curl
                  ripgrep
                  fd
                  tree
                  just
                  jq
                  tmux
                  neovim
                ]) ++ packages; # <-- will be project specific

              # settings for openssh 
              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = false;
                  KbdInteractiveAuthentication = false;
                  PermitRootLogin = "no";
                };
                # automatcally open port 22
                openFirewall = true;
              };

              # Networking: bring up the microVM NIC via DHCP
              networking.useNetworkd = true;
              systemd.network.enable = true;
              systemd.network.networks."10-ethernet" = {
                matchConfig.Name = "en* eth*";
                networkConfig.DHCP = "yes";
              };


              # user "dev" is part of wheel 
              # set authorizedKeys -> host public SSH key
              users.users.dev =
              let
                keys = if builtins.isList authorizedKeys then authorizedKeys else [ authorizedKeys ];
              in
              {
                isNormalUser = true;
                extraGroups = [ "wheel" ];
                openssh.authorizedKeys.keys = keys;
                # set fish shell as default shell
                shell = pkgs.fish;
                initialPassword = "dev";
              };

              # enable root for dev user
              security.sudo = {
                enable = true;
                wheelNeedsPassword = false;
              };

              # at init -> cd into project repo which is mounted at /workspace
              programs.fish = {
                enable = true;
                interactiveShellInit = ''
                  cd /workspace
                '';
              };

              # VM settings
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

                # mount project src dir into /workspace
                shares = [
                  {
                    proto = "9p";
                    tag = "workspace";
                    source = projectDir;
                    mountPoint = "/workspace";
                  }
                ];

                # no persistent volumes! Be sure to manually copy any files you need 
                # through SSH or creating something here. 
                volumes = [ ];
              };
            })
          ];
        };
    in
    mkSandboxSystem
