{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;
  cfg = config.services.openorange;
  workloads = cfg.workloads;
  names = builtins.attrNames workloads;
  unitNames = map (n: "docker-orange-${n}.service") names;
  engineConfig = pkgs.writeText "rivet.json" (
    builtins.toJSON {
      storage = {
        log_directory = "/var/lib/rivet/log";
        auto_provision_partitions = 1;
        balancing.enabled = false;
      };
      object_storage.primary.file_system.path = "/var/lib/rivet/objects";
    }
  );
  ports = lib.mapAttrsToList (_: w: w.port) workloads;
  internalPorts = lib.mapAttrsToList (_: w: w.internalPort) workloads;
in
{
  options.services.openorange = {
    enable = mkEnableOption "single-host OpenOrange control plane and Worker nodes";
    engineImage = mkOption {
      type = types.str;
      default = "rivetdev/engine:3.1.2-rc.1@sha256:6e585002b700dd4d3630808eb67884aa15d1a602d83781984edac47023b6d40f";
      description = "Pinned Rivet Engine image; update deliberately after a backup.";
    };
    workloads = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            image = mkOption {
              type = types.str;
              description = "Orange-generated Docker image, preferably pinned by digest.";
            };
            port = mkOption {
              type = types.port;
              description = "Nginx port exposed only on tailscale0.";
            };
            internalPort = mkOption {
              type = types.port;
              description = "Unique loopback Worker port, different from public port.";
            };
            memory = mkOption {
              type = types.str;
              default = "2g";
            };
            cpus = mkOption {
              type = types.str;
              default = "2";
            };
            environmentFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Root-owned runtime Docker env file for application secrets.";
            };
          };
        }
      );
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (n: builtins.match "[a-z][a-z0-9-]*" n != null) names;
        message = "Workload names must match [a-z][a-z0-9-]*.";
      }
      {
        assertion =
          builtins.length (
            lib.unique (
              ports
              ++ internalPorts
              ++ [
                22
                6420
                6421
              ]
            )
          ) == builtins.length (
            ports
            ++ internalPorts
            ++ [
              22
              6420
              6421
            ]
          );
        message = "OpenOrange, SSH and Engine ports must be unique.";
      }
    ];
    virtualisation.docker.enable = true;
    virtualisation.docker.daemon.settings.log-driver = "journald";
    virtualisation.oci-containers.backend = "docker";
    systemd.tmpfiles.rules = [
      "d /var/lib/openorange 0700 root root -"
      "d /var/lib/openorange/log 0700 root root -"
      "d /var/lib/openorange/objects 0700 root root -"
      "d /var/lib/openorange/workloads 0700 root root -"
      "d /var/lib/openorange/secrets 0700 root root -"
    ]
    ++ map (n: "d /var/lib/openorange/workloads/${n} 0700 root root -") names;
    virtualisation.oci-containers.containers = {
      rivet = {
        image = cfg.engineImage;
        environmentFiles = [ "/var/lib/openorange/secrets/engine.env" ];
        volumes = [
          "${engineConfig}:/etc/rivet/config.json:ro"
          "/var/lib/openorange/log:/var/lib/rivet/log"
          "/var/lib/openorange/objects:/var/lib/rivet/objects"
        ];
        extraOptions = [
          "--network=host"
          "--memory=2g"
          "--cpus=2"
          "--stop-timeout=660"
        ];
      };
    }
    // lib.mapAttrs' (
      n: w:
      lib.nameValuePair "orange-${n}" {
        image = w.image;
        environment = {
          RIVET_ENDPOINT = "http://127.0.0.1:6420";
          RIVET_NAMESPACE = "default";
          RIVET_POOL = n;
          RIVET_NODE_VERSION = w.image;
        };
        environmentFiles = lib.optional (w.environmentFile != null) w.environmentFile ++ [
          "/var/lib/openorange/secrets/worker.env"
        ];
        cmd = [
          "orange"
          "serve"
          "--ip"
          "127.0.0.1"
          "--port"
          (toString w.internalPort)
        ];
        volumes = [ "/var/lib/openorange/workloads/${n}:/app/.open-orange" ];
        extraOptions = [
          "--network=host"
          "--memory=${w.memory}"
          "--cpus=${w.cpus}"
          "--stop-timeout=1800"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
        ];
      }
    ) workloads;
    systemd.services = {
      openorange-secrets = {
        description = "Generate persistent Rivet token outside the Nix store";
        wantedBy = [ "multi-user.target" ];
        before = [ "docker-rivet.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        path = [
          pkgs.openssl
          pkgs.coreutils
        ];
        script = ''
          set -eu
          dir=/var/lib/openorange/secrets
          install -d -m 700 "$dir"
          if [ ! -s "$dir/token" ]; then
            openssl rand -hex 32 > "$dir/token.new"
            mv "$dir/token.new" "$dir/token"
          fi
          token=$(cat "$dir/token")
          printf 'RIVET__AUTH__ADMIN_TOKEN=%s\n' "$token" > "$dir/engine.env.new"
          printf 'RIVET_TOKEN=%s\n' "$token" > "$dir/worker.env.new"
          mv "$dir/engine.env.new" "$dir/engine.env"
          mv "$dir/worker.env.new" "$dir/worker.env"
        '';
      };

      docker-rivet = {
        requires = [ "openorange-secrets.service" ];
        after = [ "openorange-secrets.service" ];
        serviceConfig.TimeoutStopSec = lib.mkForce 700;
      };
      openorange-pools = {
        description = "Wait for Rivet storage and create each Worker pool";
        requires = [ "docker-rivet.service" ];
        after = [ "docker-rivet.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 10;
          TimeoutStartSec = 300;
        };
        path = [
          pkgs.curl
          pkgs.coreutils
        ];
        script = ''
          set -eu
          token=$(cat /var/lib/openorange/secrets/token)
          # Retry authenticated pool creation too: /health precedes storage readiness.
          ${lib.concatMapStringsSep "\n" (n: ''
            ready=0
            for attempt in $(seq 1 90); do
              if printf 'header = "Authorization: Bearer %s"\n' "$token" | curl --config - --silent --show-error --fail \
                --connect-timeout 2 --max-time 5 -X PUT \
                -H 'Content-Type: application/json' -d '{"drain_on_version_upgrade":true}' \
                'http://127.0.0.1:6420/pools/${n}?namespace=default' > /dev/null; then
                ready=1; break
              fi
              sleep 2
            done
            [ "$ready" = 1 ] || exit 1
          '') names}
        '';
      };
    }
    // lib.genAttrs (map (n: "docker-orange-${n}") names) (_: {
      requires = [ "openorange-pools.service" ];
      after = [ "openorange-pools.service" ];
      serviceConfig.TimeoutStopSec = lib.mkForce 1840;
    });
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = ports;
    services.nginx = {
      enable = names != [ ];
      recommendedProxySettings = true;
      virtualHosts = lib.mapAttrs' (
        n: w:
        lib.nameValuePair "${n}.local" {
          listen = [
            {
              addr = "0.0.0.0";
              port = w.port;
            }
          ];
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString w.internalPort}";
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_set_header Host $http_host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_read_timeout 3600s;
              proxy_send_timeout 3600s;
            '';
          };
        }
      ) workloads;
    };
    environment.etc."openorange/units".text = lib.concatStringsSep "\n" unitNames + "\n";
  };
}
