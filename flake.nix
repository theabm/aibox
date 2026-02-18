{
  description = "my description";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    inherit (pkgs) lib;
    authorizedKeys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO4i3B/ShuuG5zvddLbazGYNEfat3C8TF7d5ixARpHUb andres@dede"];
    unit = "aibox";
    hostPort = 2222;

    vmExe = lib.getExe self.nixosConfigurations.my-vm.config.system.build.vm;

    mkApp = name: text: {
      type = "app";
      program = "${pkgs.writeShellScript name text}";
    };

    aiboxShare = pkgs.writeShellApplication {
      name = "aibox-share";
      runtimeInputs = with pkgs; [ coreutils gnugrep util-linux bindfs fuse3 fuse ];
      text = builtins.readFile ./scripts/aibox-share;
    };

    aiboxPanelToggle = pkgs.writeShellApplication {
      name = "aibox-panel-toggle";
      runtimeInputs = with pkgs; [ coreutils ];
      text = builtins.readFile ./scripts/aibox-panel-toggle;
    };

    aiboxHeader = pkgs.writeShellApplication {
      name = "aibox-header";
      runtimeInputs = with pkgs; [ coreutils ncurses netcat-openbsd ];
      text = builtins.readFile ./scripts/aibox-header;
    };

    aiboxBrowser = pkgs.writeShellApplication {
      name = "aibox-browser";
      runtimeInputs = with pkgs; [ coreutils yazi aiboxShare aiboxPanelToggle ];
      text = builtins.readFile ./scripts/aibox-browser;
    };

    aiboxUi = pkgs.writeShellApplication {
      name = "aibox";
      runtimeInputs = with pkgs; [ coreutils tmux aiboxShare aiboxHeader aiboxBrowser ];
      text = builtins.readFile ./scripts/aibox;
    };
  in {
    nixosConfigurations.my-vm = pkgs.nixos [
      (import ./core.nix { inherit authorizedKeys; })
      ./configuration.nix
    ];

    packages.${system} = {
      default = pkgs.writeShellScriptBin "run" ''
        set -euxo pipefail
        # exec ${vmExe}
      '';
      aibox = aiboxUi;
      aibox-share = aiboxShare;
      aibox-panel-toggle = aiboxPanelToggle;
    };

    apps.${system} = {
      aibox = {
        type = "app";
        program = "${aiboxUi}/bin/aibox";
      };

      aibox-start = mkApp "aibox-start" ''
        set -euxo pipefail
        readonly AIBOX_HOME="$HOME/.aibox"
        readonly AIBOX_SHARE="$AIBOX_HOME/share"
        readonly AIBOX_SHARES="$AIBOX_HOME/shares.txt"
        mkdir -p "$AIBOX_HOME" "$AIBOX_SHARE"
        touch "$AIBOX_SHARES"
        ${aiboxShare}/bin/aibox-share sync
        echo "Starting VM (${unit}) on port ${toString hostPort}..."

        nohup ${vmExe} >"$AIBOX_HOME/nohup.out" 2>&1 &
        disown || true
      '';

      aibox-stop = mkApp "aibox-stop" ''
        set -euxo pipefail
        exec env TERM=xterm-256color ssh \
          -o UserKnownHostsFile=/dev/null \
          -o StrictHostKeyChecking=no \
          -p ${toString hostPort} \
          dev@localhost "sudo poweroff"
      '';

      aibox-clean = mkApp "aibox-clean" ''
        set -euxo pipefail
        readonly AIBOX_HOME="$HOME/.aibox"
        readonly AIBOX_SHARE="$AIBOX_HOME/share"
        readonly AIBOX_SHARES="$AIBOX_HOME/shares.txt"
        mkdir -p "$AIBOX_HOME" "$AIBOX_SHARE"
        touch "$AIBOX_SHARES"
        ${aiboxShare}/bin/aibox-share clear
        rm -f "$AIBOX_HOME/vm.qcow2" "$AIBOX_HOME/nohup.out" "$AIBOX_SHARES" "$AIBOX_HOME/tmux.sock"
        rmdir "$AIBOX_SHARE" "$AIBOX_HOME" 2>/dev/null || true
      '';

      aibox-port = mkApp "aibox-port" ''
        echo ${toString hostPort}
      '';

      aibox-ssh = mkApp "aibox-ssh" ''
        exec env TERM=xterm-256color ssh \
          -o UserKnownHostsFile=/dev/null \
          -o StrictHostKeyChecking=no \
          -p ${toString hostPort} \
          dev@localhost
      '';

      aibox-add = mkApp "aibox-use" ''
        set -euxo pipefail
        if [ "$#" -ne 1 ]; then
          echo "Usage: aibox-use /path/to/project" >&2
          exit 2
        fi
        PROJECT="$1"
        if [ ! -e "$PROJECT" ]; then
          echo "Not found: $PROJECT" >&2
          exit 2
        fi
        PROJECT="$(${pkgs.coreutils}/bin/realpath "$PROJECT")"
        ${aiboxShare}/bin/aibox-share add "$PROJECT"
      '';
    };
  };
}
