{nixpkgs, ... }:
    let
      # Function that builds a NixOS VM system for a given project + package list.
      mkSandboxSystem =
        { system
        , projectDir
        , authorizedKeys 
        , hostname ? "agent-aibox"
        , packages ? []
        , hostPort ? 2222
        , vcpu ? 4
        , mem ? 4096
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ({ pkgs, ... }: {
              system.name = hostname;
              system.stateVersion = "25.11";
              networking.hostName = hostname;
              nixpkgs.config.allowUnfree = true;

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

              # Networking: bring up the VM NIC via DHCP
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
              virtualisation = {
                memorySize = mem;
                cores = vcpu;

                forwardPorts = [
                  { from = "host"; host.port = hostPort; guest.port = 22; }
                ];

                # mount project src dir into /workspace
                sharedDirectories = {
                  workspace = {
                    source = projectDir;
                    target = "/workspace";
                  };
                };
              };
            })
          ];
        };
    in
    mkSandboxSystem
