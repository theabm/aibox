{ pkgs, ... }:
{
  environment.systemPackages =
  (with pkgs; [
    # I use fish shell
    fish

    # useful in general
    git
    curl
    ripgrep
    fd
    tree
    just
    jq
    tmux
    neovim
    lazygit

    # AI 
    codex
    claude-code

    # python
    uv
    ruff

    jetbrains.pycharm
    opencode
    code-cursor
    vscode

    # nodejs for mcp 
    nodejs

  ]);


  system.stateVersion = "26.05";
}
