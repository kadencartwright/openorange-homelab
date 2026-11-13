# Ubuntu remains the K3s host. Give its OpenOrange VM most of this 16-thread,
# 28-GiB machine, with a reserve for the host and its existing cluster services.
{ lib, ... }: {
  imports = [ ../../modules/folio.nix ];
  services.folioHomelab.enable = true;
  virtualisation = {
    cores = lib.mkForce 12;
    memorySize = lib.mkForce 22528;
    diskSize = lib.mkForce 57344;
  };
  services.openorange.workloads.hello.image = lib.mkForce "localhost/openorange-campfire:1";
}
