{ pkgs, ... }:
let
  settings = builtins.fromJSON (builtins.readFile ./settings.json);
in
{
  imports = [ ./hardware-configuration.nix ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.tmp.cleanOnBoot = true;
  networking.hostName = settings.hostname;
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.firewall.checkReversePath = "loose";
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  users.users.lab = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = settings.sshAuthorizedKeys;
  };
  security.sudo.wheelNeedsPassword = false;
  services.journald.settings.Journal.SystemMaxUse = "512M";
  services.fstrim.enable = true;
  services.openorange.enable = true;
  environment.systemPackages = with pkgs; [
    git
    curl
    jq
    htop
    tmux
    openssl
  ];
  time.timeZone = settings.timeZone;
  system.stateVersion = "26.05";
}
