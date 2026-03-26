{
  description = "Nix devshells for XiangShan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
  };

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    smokeInputs = with pkgs; [
      bash
      coreutils
      findutils
      git
      gnumake
      gnugrep
      gnused
      nix
      pkgsCross.riscv64.buildPackages.gcc
    ];
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        autoconf
        bear
        bison
        clang
        cmake
        curl
        direnv
        dtc
        flex
        gcc
        git
        git-lfs
        glib
        gnumake
        gtkwave
        libcap_ng
        libslirp
        llvm
        openjdk
        pixman
        pkg-config
        pkgsCross.riscv64.buildPackages.gcc
        python3
        python3Packages.psutil
        readline
        SDL2
        sqlite
        time
        tmux
        wget
        zlib
        zstd
        (mill.overrideAttrs (finalAttrs: _: {
          version = "0.12.15";
          src = pkgs.fetchurl {
            url = "https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/${finalAttrs.version}/mill-dist-${finalAttrs.version}.exe";
            hash = "sha256-6hu6AeIg9M4guzMyR9JUor+bhlVMEMPX1+FmQewKdtg=";
          };
        }))
        (verilator.overrideAttrs (finalAttrs: _: {
          version = "5.040";
          VERILATOR_SRC_VERSION = "v${finalAttrs.version}";
          src = pkgs.fetchFromGitHub {
            owner = "verilator";
            repo = "verilator";
            rev = "v${finalAttrs.version}";
            hash = "sha256-S+cDnKOTPjLw+sNmWL3+Ay6+UM8poMadkyPSGd3hgnc=";
          };
          doCheck = false;
        }))
      ];
      shellHook = ''
        export XSAI_ENV_QUIET=1
        source ./scripts/env-common.sh
        xsai_env_init

        echo "=== Welcome to XiangShan devshell! ==="
        echo "Version info:"
        echo "- $(verilator --version)"
        echo "- $(mill --version | head -n 1)"
        echo "- $(gcc --version | head -n 1)"
        echo "- $(riscv64-unknown-linux-gnu-gcc --version | head -n 1)"
        echo "- $(java -version 2>&1 | head -n 1)"
        echo "You can press Ctrl + D to exit devshell."
        export LD_LIBRARY_PATH="${pkgs.zlib}/lib:${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
      '';
    };

    checks.${system}.smoke = pkgs.runCommand "xsai-smoke" {
      nativeBuildInputs = smokeInputs;
      src = ./.;
    } ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      cp -R "$src" repo
      chmod -R u+w repo
      cd repo
      bash ./scripts/smoke-test.sh --mode nix
      touch "$out"
    '';
  };
}
