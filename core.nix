{authorizedKeys, ... }:
let
  workdir = "/workspace";
  uid = 1000;
in
{config, ... }: {
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix
  virtualisation.vmVariant.virtualisation = {
    graphics = false;
    memorySize = 1024 * 4;
    cores = 4;
    diskImage = "$HOME/.aibox/vm.qcow2";
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
    sharedDirectories = {
      work = {
        source = "$HOME/.aibox";
        target = workdir;
      };
    };
  };

  system.name = "aibox";
  networking.hostName = "aibox";
  users.users.dev =
    let
      keys = if builtins.isList authorizedKeys then authorizedKeys else [ authorizedKeys ];
    in
      {
      inherit uid;
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = keys;
      # set fish shell as default shell
      shell = config.programs.fish.package;
      initialPassword = "dev";
    };

  services.getty.autologinUser = "dev";
  security.sudo.wheelNeedsPassword = false;
  programs.fish = {
    enable = true;
    interactiveShellInit = "cd /workspace";
  };


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
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-ethernet" = {
    matchConfig.Name = "en* eth*";
    networkConfig.DHCP = "yes";
  };



}
