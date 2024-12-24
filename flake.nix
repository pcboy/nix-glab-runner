{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        builders = {
          gceImage =
            {
              extraModules ? [ ],
            }:
            nixos-generators.nixosGenerate {
              system = "x86_64-linux";

              modules = [
                ./configuration.nix
              ] ++ extraModules;
              format = "gce";

              pkgs = nixpkgs.legacyPackages.x86_64-linux;
              lib = nixpkgs.legacyPackages.x86_64-linux.lib;
            };
          uploadGceImage =
            {
              bucket,
              gceImage,
              imagePrefixName,
            }:
            let
              imgId = pkgs.runCommand "sanitizedImgId" { } ''
                echo -n ${imagePrefixName} | ${pkgs.gnused}/bin/sed 's|.raw.tar.gz$||;s|\.|-|g;s|_|-|g' > $out
              '';
            in
            pkgs.writeShellScriptBin "handler" ''
              set -euo pipefail

              ${pkgs.google-cloud-sdk}/bin/gsutil cp ${gceImage}/*.raw.tar.gz "gs://${bucket}/${imagePrefixName}.raw.tar.gz"
              ${pkgs.google-cloud-sdk}/bin/gcloud compute images create ${builtins.readFile imgId} \
                --source-uri "gs://${bucket}/${imagePrefixName}.raw.tar.gz" \
                --family="nixos-image-gitlab-runner" \
                --guest-os-features=GVNIC
            '';
        };
      }
    );
}
