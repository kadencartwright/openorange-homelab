{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
  networking.hostName = lib.mkForce "orangebox-vm";
  virtualisation = {
    memorySize = 8192;
    cores = 4;
    diskSize = 40960;
    graphics = false;
    # The host share contains only the management public key.
    sharedDirectories.shared.writable = lib.mkForce false;
    sharedDirectories.shared.source = lib.mkForce ''"$OPENORANGE_VM_STATE_DIR/share"'';
    fileSystems."/tmp/shared".options = lib.mkAfter [ "ro" ];
    qemu.options = [
      "-enable-kvm"
      "-cpu"
      "host"
    ];
    forwardPorts = [
      {
        host.address = "127.0.0.1";
        host.port = 22222;
        guest.port = 22;
      }
    ];
  };
  # Only this VM's NAT interface allows bootstrap SSH. The host forward is loopback-only.
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ 22 ];
  services.openssh.authorizedKeysFiles = [ "/run/openorange-vm-keys/%u" ];
  systemd.services.openorange-vm-management = {
    description = "Install host-provided public key for local VM management";
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    unitConfig.RequiresMountsFor = "/tmp/shared";
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.coreutils}/bin/install -D -m 0644 /tmp/shared/management.pub /run/openorange-vm-keys/lab
    '';
  };
  services.openorange.workloads.hello = {
    image = "localhost/openorange-hello:1";
    port = 8080;
    internalPort = 18080;
  };
}
