{
  pkgs,
  modulesPath,
  lib,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
  ];

  config = {
    system.stateVersion = "23.11";
    boot.kernel.sysctl."net.ipv4.ip_forward" = true;

    networking.nameservers = ["8.8.8.8"];

    virtualisation.containers.enable = true;
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };

    nix = {
      settings.auto-optimise-store = true;
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    services.openssh.settings.PasswordAuthentication = false;

    services.gitlab-runner = {
      enable = true;
      settings = {
        concurrent = 4;
        checkInterval = 30;
      };
      services = {
        # runner for building in docker via host's nix-daemon
        # nix store will be readable in runner, can be insecure if no control over the host
        nix = with lib; {
          registrationConfigFile = "/etc/gitlab-runner-env";
          dockerImage = "alpine";
          dockerVolumes = [
            "/certs/client"
            "/cache"
            "/nix/store:/nix/store:ro"
            "/nix/var/nix/db:/nix/var/nix/db:ro"
            "/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket:ro"
            "/var/run/docker.sock:/var/run/docker.sock"
          ];
          dockerDisableCache = false;
          dockerPrivileged = true;

          preBuildScript = pkgs.writeScript "setup-container" ''
            ${pkgs.coreutils}/bin/mkdir -p -m 0755 /nix/var/log/nix/drvs
            ${pkgs.coreutils}/bin/mkdir -p -m 0755 /nix/var/nix/gcroots
            ${pkgs.coreutils}/bin/mkdir -p -m 0755 /nix/var/nix/profiles
            ${pkgs.coreutils}/bin/mkdir -p -m 0755 /nix/var/nix/temproots
            ${pkgs.coreutils}/bin/mkdir -p -m 0755 /nix/var/nix/userpool
            ${pkgs.coreutils}/bin/mkdir -p -m 1777 /nix/var/nix/gcroots/per-user
            ${pkgs.coreutils}/bin/mkdir -p -m 1777 /nix/var/nix/profiles/per-user
            ${pkgs.coreutils}/bin/mkdir -p -m 0755 /nix/var/nix/profiles/per-user/root
            ${pkgs.coreutils}/bin/mkdir -p -m 0700 "$HOME/.nix-defexpr"

            . ${pkgs.nix}/etc/profile.d/nix.sh

            ${pkgs.nix}/bin/nix-env -i ${lib.concatStringsSep " " (with pkgs; [nix cacert gnugrep git coreutils bash openssh])}
          '';
          environmentVariables = {
            ENV = "/etc/profile";
            USER = "root";
            NIX_REMOTE = "daemon";
            # Careful: This PATH will be shared with the containers gitlab-runner execute.
            # We need to have /usr/local/bin in it if we are using the postgres service in gitlab-ci.yml
            #      PATH = "/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
            NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
            DOCKER_DRIVER = "overlay2";
            DOCKER_TLS_VERIFY = "1";
            DOCKER_CERT_PATH = "/certs/client";
            FF_NETWORK_PER_BUILD = "true";
          };
          tagList = ["nix-runner-docker"];
        };
      };
    };
  };
}
