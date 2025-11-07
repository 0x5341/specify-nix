{
  description = "github spec-kit cli";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    specify = {
      url = "github:github/spec-kit";
      flake = false;
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      utils,
      specify,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    utils.lib.eachSystem utils.lib.allSystems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        generate-lock = pkgs.writeScriptBin "genlock" ''
          #! /bin/sh
          git clone --depth 1 https://github.com/github/spec-kit.git ./spec-kit 
          cd spec-kit
          ${pkgs.uv}/bin/uv lock
          mv uv.lock ../uv.lock
          cd ..
          rm -rf ./spec-kit
        '';

        add-file =
          path1: path2: path3:
          pkgs.runCommand "add-file" { } ''
            mkdir -p $out
            cp -r ${path3}/* $out/
            cp -r ${path1} $out/${path2}
          '';

        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = add-file ./uv.lock "uv.lock" specify;
        };

        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

        pythonSets =
          let
            python = pkgs.python3;
          in
          (pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          }).overrideScope
            (
              nixpkgs.lib.composeManyExtensions [
                pyproject-build-systems.overlays.wheel
                overlay
              ]
            );
        
        pick-bin = drv_path: name: pkgs.runCommand "pick-bin" {} ''
          mkdir -p $out/bin
          ln -s ${drv_path} $out/bin/${name}
        '';
      in
      {
        apps = {
          genlock = {
            type = "app";
            program = "${generate-lock}/bin/genlock";
          };
        };
        packages = {
          default = pick-bin "${pythonSets.mkVirtualEnv "specify" workspace.deps.default}/bin/specify" "specify";
        };
      }
    );
}
