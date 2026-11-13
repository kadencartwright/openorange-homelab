{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.folioHomelab;
  engineConfig = pkgs.writeText "folio-rivet.json" (
    builtins.toJSON {
      metrics = {
        host = "127.0.0.1";
        port = 6450;
      };
      guard = {
        host = "127.0.0.1";
        port = 6440;
      };
      api_peer = {
        host = "127.0.0.1";
        port = 6441;
        advertise_address = "127.0.0.1:6441";
      };
      storage = {
        log_directory = "/var/lib/rivet/log";
        auto_provision_partitions = 1;
        balancing.enabled = false;
      };
      object_storage.primary.file_system.path = "/var/lib/rivet/objects";
    }
  );
  source = builtins.fromJSON (builtins.readFile ../apps/folio/source.json);
in
{
  options.services.folioHomelab = {
    enable = lib.mkEnableOption "independent Folio library on an isolated OpenOrange Engine";
    origin = lib.mkOption {
      type = lib.types.str;
      default = "http://100.96.205.20:8081";
    };
    adminEmail = lib.mkOption {
      type = lib.types.str;
      default = "admin@example.com";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.python3 ];
    environment.etc."folio/origin".text = cfg.origin;
    assertions = [
      {
        assertion = config.services.openorange.enable;
        message = "Folio requires the OpenOrange host Docker configuration.";
      }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/folio 0700 root root -"
    ]
    ++ map (p: "d /var/lib/folio/${p} 0700 root root -") [
      "log"
      "objects"
      "worker"
      "secrets"
    ];
    systemd.services.folio-secrets = {
      before = [ "docker-folio-engine.service" ];
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
        dir=/var/lib/folio/secrets
        install -d -m 700 "$dir"
        for name in engine-token auth-secret; do
          if [ ! -s "$dir/$name" ]; then openssl rand -hex 32 > "$dir/$name.new"; mv "$dir/$name.new" "$dir/$name"; fi
        done
        token=$(cat "$dir/engine-token")
        secret=$(cat "$dir/auth-secret")
        printf 'RIVET__AUTH__ADMIN_TOKEN=%s\n' "$token" > "$dir/engine.env"
        printf 'RIVET_TOKEN=%s\nAUTH_SECRET=%s\n' "$token" "$secret" > "$dir/worker.env"
      '';
    };
    virtualisation.oci-containers.containers = {
      folio-engine = {
        image = config.services.openorange.engineImage;

        environmentFiles = [ "/var/lib/folio/secrets/engine.env" ];
        volumes = [
          "${engineConfig}:/etc/rivet/config.json:ro"
          "/var/lib/folio/log:/var/lib/rivet/log"
          "/var/lib/folio/objects:/var/lib/rivet/objects"
        ];
        extraOptions = [
          "--network=host"
          "--memory=2g"
          "--cpus=2"
          "--stop-timeout=660"
        ];
      };
      folio = {
        image = source.image;
        environment = {
          RIVET_ENDPOINT = "http://127.0.0.1:6440";
          RIVET_NAMESPACE = "default";
          AUTH_ORIGIN = cfg.origin;
          ADMIN_EMAILS = cfg.adminEmail;
          ORANGE_WORKER_VARS = "AUTH_ORIGIN,ADMIN_EMAILS";
          ORANGE_WORKER_SECRETS = "AUTH_SECRET";
        };
        environmentFiles = [ "/var/lib/folio/secrets/worker.env" ];
        volumes = [ "/var/lib/folio/worker:/app/.open-orange" ];
        cmd = [
          "orange"
          "serve"
          "--config"
          "wrangler.homelab.json"
          "--ip"
          "127.0.0.1"
          "--port"
          "18081"
        ];
        extraOptions = [
          "--network=host"
          "--memory=4g"
          "--cpus=4"
          "--stop-timeout=1800"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
        ];
      };
    };
    systemd.services.docker-folio-engine = {
      requires = [ "folio-secrets.service" ];
      after = [ "folio-secrets.service" ];
      serviceConfig.TimeoutStopSec = lib.mkForce 700;
    };
    systemd.services.folio-pool = {
      requires = [ "docker-folio-engine.service" ];
      after = [ "docker-folio-engine.service" ];
      path = [
        pkgs.curl
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 300;
      };
      script = ''
        set -eu
        token=$(cat /var/lib/folio/secrets/engine-token)
        for _ in $(seq 1 90); do
          if printf 'header = "Authorization: Bearer %s"\n' "$token" | curl --config - -sf --max-time 5 -X PUT \
            -H 'Content-Type: application/json' -d '{}' 'http://127.0.0.1:6440/pools/default?namespace=default' > /dev/null; then exit 0; fi
          sleep 2
        done
        exit 1
      '';
    };
    systemd.services.docker-folio = {
      requires = [ "folio-pool.service" ];
      after = [ "folio-pool.service" ];
      serviceConfig.TimeoutStopSec = lib.mkForce 1840;
    };
    systemd.services.folio-migrations = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "docker-folio.service" ];
      after = [ "docker-folio.service" ];
      path = [
        pkgs.curl
        pkgs.coreutils
        pkgs.docker
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 300;
      };
      script = ''
        set -eu
        for _ in $(seq 1 90); do
          if curl -sf --max-time 5 http://127.0.0.1:18081/healthz > /dev/null; then
            exec docker exec folio orange d1 migrations apply DB --remote --config wrangler.homelab.json
          fi
          sleep 2
        done
        exit 1
      '';
    };
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8081 ];
    services.nginx.virtualHosts."folio.local" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 8081;
        }
      ];
      locations."= /api/local/mail".return = "404";
      # Local development allows open reader registration; keep it closed on the tailnet.
      locations."= /users/create".return = "404";
      locations."/" = {
        proxyPass = "http://127.0.0.1:18081";
        proxyWebsockets = true;
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_set_header Host $host:8081;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          client_max_body_size 17m;
          proxy_read_timeout 3600s;
        '';
      };
    };
  };
}
