{
  description = "";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/a7fc50310a037e6fb42d08188f7e0ff3e58379bc";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      overlays = [
        (final: prev: {
          go = prev.go_1_25;
          nodejs = prev.nodejs_22;
        })
      ];
      pkgsFor = system: import nixpkgs {
        inherit system overlays;
      };
      pkgsCrossFor = system: target: import nixpkgs {
        inherit system overlays;
        crossSystem = target;
      };

      #Use this one when updating packages, it's failsafe non-cached one
      #vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      vendorHash = "sha256-Np6qkhmGjpN/6fIP2riieuSALpbhpRgTp1RayNt9fg8=";

      buildNsc = pkgs:
        pkgs.buildGoModule {
          inherit vendorHash;

          version = "4.0";
          pname = "nsc";

          src = ./.;
          subPackages = [
            "cmd/go-smart-controller"
            "cmd/pb-smart-controller"
            "cmd/substation"
            "cmd/bitcoin"
            "cmd/weather"
          ];

          env = {
            CGO_ENABLED = 0;
          };

          checkPhase = ''
            if [ -n "$CI" ]; then
              go test ./...
            else
              echo "Skipping test when CI not set"
            fi
          '';
        };

      buildBrains = pkgs:
        pkgs.buildGoModule {
          inherit vendorHash;

          version = "4.0";
          pname = "brains";

          src = ./.;
          subPackages = [
            "cmd/brains"
          ];

          env = {
            CGO_ENABLED = 0;
          };

          checkPhase = ''
            if [ -n "$CI" ]; then
              go test ./...
            else
              echo "Skipping test when CI not set"
            fi
          '';
        };
    in {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          imageTag = "latest";
          arch = {
            "x86_64-linux" = "amd64";
            "aarch64-linux" = "arm64";
          };
        in rec {
          nsc = buildNsc pkgs;
          brains = buildBrains pkgs;
          crossNsc = forAllSystems (target: buildNsc (pkgsCrossFor system target));
          crossBrains = forAllSystems (target: buildBrains (pkgsCrossFor system target));
          dockerImage = {
            "nsc" = forAllSystems (target: pkgs.dockerTools.buildLayeredImage {
              name = "ghcr.io/cnuss/smart-controller";
              tag = "${imageTag}-${target}";
              architecture = arch.${target};
              contents = [
                pkgs.cacert
                crossNsc.${target}
              ];
            });
            "brains" = forAllSystems (target: pkgs.dockerTools.buildLayeredImage {
              name = "ghcr.io/cnuss/brains";
              tag = "${imageTag}-${target}";
              architecture = arch.${target};
              contents = [
                pkgs.cacert
                crossBrains.${target}
              ];
            });
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.go
              pkgs.nodejs
              pkgs.typescript-language-server
              pkgs.yarn
              pkgs.buf
              pkgs.protobuf
              pkgs.protoc-gen-go
              pkgs.protoc-gen-go-grpc
              pkgs.protoc-gen-connect-go
              pkgs.sqlc
            ];

            shellHook = ''
              # Make sure Go always has a valid temp dir
              export TMPDIR=/tmp
            '';
          };
        }
      );
    };
}