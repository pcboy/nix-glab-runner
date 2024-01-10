# Nix GLab Runner

## Intro

I had a hard time just following the NixOS GitLab runner doc and make it work.  
Notably, it took a long time to have stuff like CI `services` working.  
This flake is working for me at the moment of writing this document.  
The current setup let you share the /nix/store between jobs (careful: this can be potentially insecure if you don't trust your CI users and put sensitive stuff in /nix/store).

## Usage

Flake example:

```nix
{
  description = "A basic flake with a shell";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix-glab-runner.url = "github:pcboy/nix-glab-runner";

  outputs = {
    nixpkgs,
    flake-utils,
    nix-glab-runner,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      glabBuilders = nix-glab-runner.builders.${system};
    in {
      devShells.default = pkgs.mkShell {
        packages = [pkgs.bashInteractive];
      };

      packages.uploadGceImage = glabBuilders.uploadGceImage {
        bucket = "gitlab-runner-images-nix";
        gceImage = glabBuilders.gceImage {};
        imagePrefixName = "nixos-image-23.11.x86_64-linux";
      };
    });
}
```

Then to build the GCE image locally, then upload it, and create the compute image on GCP, you just do:

```shell
$> nix run .\#uploadGceImage
Copying file:///nix/store/zx0c1gm76q2gzgy6yvcr3pa3mlnxbkah-google-compute-image/nixos-image-23.11.20240108.6723fa4-x86_64-linux.raw.tar.gz [Content-Type=application/x-tar]...
\ [1 files][681.9 MiB/681.9 MiB]   29.4 MiB/s
Operation completed over 1 objects/681.9 MiB.
Created [https://www.googleapis.com/compute/v1/projects/my-project/global/images/nixos-image-23-11-x86-64-linux].
NAME                            PROJECT               FAMILY                     DEPRECATED  STATUS
nixos-image-23-11-x86-64-linux  my-project  nixos-image-gitlab-runner              READY
```

The last line shows that it's now there and ready to be used. You just have to create a new instance on GCP using it.

Note:

As you can see, there is no GitLab token asked anywhere.  
It's because I expect you to add it in the startup script of the instance, it needs to get written in `/etc/gitlab-runner-env`.  
For instance, create a `startup.sh` looking like:

```shell
printf "CI_SERVER_URL=https://gitlab.com\nREGISTRATION_TOKEN=glrt-YOUR_TOKEN" > /etc/gitlab-runner-env
```

You can then create an instance with:

```shell
#!/usr/bin/env nix-shell
#!nix-shell -i bash -p google-cloud-sdk

gcloud compute instances create gitlab-runner-nix \
    --project=my-project \
    --zone=us-central1-a \
    --machine-type=e2-standard-4 \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=us-central1-pri-net \
    --metadata=enable-oslogin=TRUE \
    --can-ip-forward \
    --provisioning-model=SPOT \
    --service-account=gitlab-ci-runner@my-project.iam.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name=gitlab-runner-nix,image=projects/my-project/global/images/nixos-image-23-11-x86-64-linux,mode=rw,size=100,type=projects/my-project/zones/us-central1-a/diskTypes/pd-balanced \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any \
    --metadata-from-file startup-script=./startup.sh
```

As you can see, I'm using `--metadata-from-file` to specify the startup-script. Then, when the instance starts, it will add the GitLab token at the correct place.  
That's just an easy setup, but you could do it completely differently, like using Vault or whatever, it's up to you.

Note: `enable-oslogin=TRUE` is important if you want to be able to sudo to get root on the instance.  
But at this moment it seems there is an upstream bug that prevents it to work. So, instead, I suggest improving the original NixOS configuration of the image to create a user and add your SSH keys. This can be done by using the `extraModules` parameter of the `gceImage` builder. For instance:

extra_config.nix

```nix
{lib, ...}: {
  users.users.pcboy = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
  };

  security.sudo.extraRules = [
    {
      users = ["pcboy"];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  users.users.pcboy.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAAAAAAAAAAAAAAAAAAAAIJYbLmIWoE5S4UAAeXoh9xjIuKMCZvFdyZmoSY+N/nEw pcboy@host"
  ];

  services.gitlab-runner.services.nix.tagList = lib.mkForce ["nix-runner-docker"];
}
```

Then:

```nix
{
  packages.uploadGceImage = glabBuilders.uploadGceImage {
    bucket = "gitlab-runner-images-nix";
    gceImage = glabBuilders.gceImage {extraModules = [./extra_config.nix];};
    imagePrefixName = "nixos-image-23.11.x86_64-linux";
  };
}
```

Note: `tagList` can also be specified. It's the list of [CI tags](https://docs.gitlab.com/ee/ci/yaml/#tags) that the runner should respond to.  
The default is `nix-gitlab-runner`, but you can overwrite it in your `extra_config.nix` by setting `services.gitlab-runner.services.nix.tagList` (see example).  
I highly recommend to look at [./configuration.nix](./configuration.nix).

# Sources

[NixOS Wiki on GitLab Runners](https://nixos.wiki/wiki/Gitlab_runner)
