{
  config, pkgs, ... }:

{
  programs.home-manager.enable = true;
  home.username = "syaofox";
  home.homeDirectory = "/home/syaofox";
  home.stateVersion = "25.05";
  programs.git.enable = true;
  programs.bash = {
    enable = true;
    shellAliases = {
      btw = "echo i use nixos, btw";
    };
  };

  # Mango window manager configuration
  wayland.windowManager.mango = {
    enable = true;
    settings = ''
      # Basic mango configuration
      # You can customize this according to your needs
    '';
    autostart_sh = ''
      # Autostart applications
      # Add your desired applications here
    '';
  };
}