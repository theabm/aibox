{
  description = "MyProjectName"; # <-- make sure to change this! The port and systemd service are set by hashing this name

  inputs = {
    aibox.url = "github:theabm/aibox";
    nixpkgs.follows = "aibox/nixpkgs";
    microvm.follows = "aibox/microvm";
  };

  outputs = { self, aibox, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      # your host publich ssh key
      authorizedKeys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO4i3B/ShuuG5zvddLbazGYNEfat3C8TF7d5ixARpHUb andres@dede"];

      pkgs = import nixpkgs {
         inherit system;
         config.allowUnfree = true;
      };

      lib = nixpkgs.lib;

      # --- Deterministic ID derived from project identifier ---
      projectId = toString ./.; # keep stable per project

      # modulo function (lacking in Nix)
      mod = a: b: a - (b * (a / b));

      # Convert hex string -> int (so we can map a hash to a port)
      hexToInt = hex:
        let
          chars = lib.stringToCharacters (lib.toLower hex);
          digit = c:
            if c == "0" then 0 else
            if c == "1" then 1 else
            if c == "2" then 2 else
            if c == "3" then 3 else
            if c == "4" then 4 else
            if c == "5" then 5 else
            if c == "6" then 6 else
            if c == "7" then 7 else
            if c == "8" then 8 else
            if c == "9" then 9 else
            if c == "a" then 10 else
            if c == "b" then 11 else
            if c == "c" then 12 else
            if c == "d" then 13 else
            if c == "e" then 14 else
            if c == "f" then 15 else
            throw "hexToInt: invalid hex digit '${c}'";
        in
          lib.foldl' (acc: c: acc * 16 + digit c) 0 chars;

      h = builtins.hashString "sha256" projectId;

      # Unit name: stable + short, avoids collisions
      unitSuffix = builtins.substring 0 10 h;
      unit = "agent-aibox-${unitSuffix}";
      hostname = unit;

      # Port range: pick a safe unprivileged block unlikely to collide
      # 20000–39999
      portSeed = hexToInt (builtins.substring 0 4 h); # 16 bits
      hostPort = 20000 + (mod portSeed  20000);

      # build VM from base + extra packages
      vm = aibox.lib.mkSandboxSystem {
        inherit system hostPort authorizedKeys hostname;
        projectDir = toString ./.;

        # per project packages go here!
        packages = with pkgs; [
          gcc
          uv

          # AI 
          claude-code
          codex
        ];
      };

      # get the vm runner
      runner = vm.config.microvm.declaredRunner;

      # utility function to an app
      mkApp = name: text: {
        type = "app";
        program = "${pkgs.writeShellScript name text}";
      };
    in
    {
      # consumed by nix build (default means `nix build .` evaluates `nix build aibox`)
      packages.${system} = {
        aibox = runner;
        default = runner;
      };

      # utility cli functions 
      apps.${system} = {
        # `nix run .#aibox` -> build (if not already built) and start the VM (need to keep terminal running!)
        aibox = {
          type = "app";
          program = "${runner}/bin/microvm-run";
        };
        # `nix run . ` will default to `nix run .#sanbox`
        default = self.apps.${system}.aibox;

        # `nix run .#sanbox-daemon`
        # (recommended) command to build + start the VM as a background systemd service 
        aibox-daemon = mkApp "aibox-daemon" ''
          set -euo pipefail

          # Stop any existing instance of this project's unit
          systemctl --user stop "${unit}" >/dev/null 2>&1 || true

          systemd-run --user \
            --unit="${unit}" \
            --collect \
            --property=Restart=on-failure \
            --property=RestartSec=2 \
            --property=KillMode=mixed \
            --property=TimeoutStopSec=10 \
            --property=StandardOutput=journal \
            --property=StandardError=journal \
            ${runner}/bin/microvm-run

          echo "Started: ${unit}"
          echo "Logs:    journalctl --user -u ${unit} -f"
          echo "Stop:    systemctl --user stop ${unit}"
          echo "SSH:     ssh -p ${toString hostPort} dev@localhost"
        '';

        # `nix run .#aibox-stop` -> stop the VM
        aibox-stop = mkApp "aibox-stop" ''
          set -euo pipefail
          systemctl --user stop "${unit}"
          echo "Stopped: ${unit}"
        '';

        # `nix run .#aibox-status` -> stop the VM
        aibox-status = mkApp "aibox-status" ''
          set -euo pipefail
          systemctl --user status "${unit}" --no-pager || true
        '';

        # `nix run .#aibox-logs` -> logs of the VM
        aibox-logs = mkApp "aibox-logs" ''
          set -euo pipefail
          journalctl --user -u "${unit}" -f
        '';

        # `nix run .#aibox-ssh` -> ssh into the VM (useful to not have to manually set port)
        aibox-ssh = mkApp "aibox-ssh" ''
          set -euo pipefail

          port=${toString hostPort}
          host=localhost
          user=dev

          echo "Connecting to aibox:"
          echo "  ssh -p $port $user@$host"
          echo

          echo "Running custom SSH command for kitty users ... Change to normal SSH if not using kitty!"
          exec env TERM=xterm-256color ssh -p "$port" dev@localhost
        '';

        # `nix run .#aibox-port` -> print the port where the VM is listening
        aibox-port = mkApp "aibox-port" ''
          set -euo pipefail
          echo ${toString hostPort}
        '';

      };
    };
}

