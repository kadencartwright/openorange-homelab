{
  description = "Bare-metal OpenOrange home lab with Tailscale";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mkHost =
        extra:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./hosts/minipc
            ./modules/openorange.nix
          ]
          ++ extra;
        };
      host = mkHost [ ];
      example = mkHost [
        {
          services.openorange.workloads.hello = {
            image = "localhost/hello:test";
            port = 8080;
            internalPort = 18080;
          };
        }
      ];
    in
    {
      nixosModules.openorange = import ./modules/openorange.nix;
      nixosConfigurations.minipc = host;
      nixosConfigurations.vm = mkHost [ ./hosts/vm ];
      formatter.${system} = pkgs.nixfmt;
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          git
          jq
          curl
          openssl
          nodejs_24
          docker-client
          shellcheck
          parted
          e2fsprogs
          dosfstools
        ];
      };
      checks.${system} = {
        scripts = pkgs.runCommand "check-scripts" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          shellcheck ${./scripts}/*.sh
          touch $out
        '';
        configuration =
          let
            cfg = example.config;
            ok =
              builtins.all (a: a.assertion) cfg.assertions
              &&
                cfg.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [
                  22
                  8080
                ]
              && cfg.networking.firewall.allowedTCPPorts == [ ]
              && cfg.virtualisation.oci-containers.containers.orange-hello.environment.RIVET_POOL == "hello"
              && cfg.systemd.services.docker-orange-hello.requires == [ "openorange-pools.service" ]
              && cfg.services.openssh.settings.PasswordAuthentication == false
              && builtins.isString cfg.system.build.toplevel.drvPath;
          in
          assert ok;
          pkgs.runCommand "check-configuration" { } "touch $out";
      };
    };
}
