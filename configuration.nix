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

    # AI 
    codex
  ]);


  system.stateVersion = "26.05";
}
