rec {
  description = "obsidize"; # <-- set this to a stable per-project identifier

  inputs = {
    base.url = "path:/home/andres/dotfiles/utils";
    nixpkgs.follows = "base/nixpkgs";
    microvm.follows = "base/microvm";
  };

  outputs = { self, base, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # --- Deterministic ID derived from project identifier ---
      projectId = description; # keep stable per project

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
      unit = "agent-sandbox-${unitSuffix}";

      # Port range: pick a safe unprivileged block unlikely to collide
      # 20000–39999
      portSeed = hexToInt (builtins.substring 0 4 h); # 16 bits
      hostPort = 20000 + (mod portSeed  20000);

      vm = base.lib.mkSandboxSystem {
        inherit system hostPort;
        projectDir = toString ./.;

        packages = with pkgs; [
          tree
          just
          gcc
          rustup
          uv
        ];
      };

      runner = vm.config.microvm.declaredRunner;

      mkApp = name: text: {
        type = "app";
        program = "${pkgs.writeShellScript name text}";
      };
    in
    {
      packages.${system} = {
        sandbox = runner;
        default = runner;
      };

      apps.${system} = {
        sandbox = {
          type = "app";
          program = "${runner}/bin/microvm-run";
        };
        default = self.apps.${system}.sandbox;

        sandbox-daemon = mkApp "sandbox-daemon" ''
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

        sandbox-stop = mkApp "sandbox-stop" ''
          set -euo pipefail
          systemctl --user stop "${unit}"
          echo "Stopped: ${unit}"
        '';

        sandbox-status = mkApp "sandbox-status" ''
          set -euo pipefail
          systemctl --user status "${unit}" --no-pager || true
        '';

        sandbox-logs = mkApp "sandbox-logs" ''
          set -euo pipefail
          journalctl --user -u "${unit}" -f
        '';

        sandbox-ssh = mkApp "sandbox-ssh" ''
          set -euo pipefail

          port=${toString hostPort}
          host=localhost
          user=dev

          echo "Connecting to sandbox:"
          echo "  ssh -p $port $user@$host"
          echo

          exec env TERM=xterm-256color ssh -p "$port" dev@localhost
        '';

        sandbox-port = mkApp "sandbox-port" ''
          set -euo pipefail
          echo ${toString hostPort}
        '';

      };
    };
}

