# Replaced by scripts/install.sh using nixos-generate-config on YOUR machine.
# This placeholder supports evaluation; do not install it unchanged.
{ lib, ... }: {
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
  ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
