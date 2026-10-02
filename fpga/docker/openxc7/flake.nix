# The openXC7 tools LiteX's `--toolchain openxc7` calls, and nothing else, taken
# from openXC7's own Nix flake (their recommended distribution) at one commit.
# Its flake.lock pins nixpkgs (and so yosys); its nix/*.nix pin nextpnr,
# prjxray and prjxray-db by commit + hash. Our flake.lock pins that commit.
#
# The official devShell also carries ghdl, openFPGALoader, fpga-as (a Bazel
# build) and sv-elab: none is on LiteX's path (yosys -> nextpnr-xilinx ->
# fasm2frames -> xc7frames2bit), so they are left out to keep the image small.
{
  description = "ZigMachine openXC7 toolchain (yosys, nextpnr-xilinx, prjxray, fasm)";
  inputs.openxc7.url = "github:openXC7/toolchain-nix/092acc1e4599a0892fe02937a15928e137ad592d";

  outputs = { self, openxc7 }:
    let
      system = "x86_64-linux";
      pkgs = openxc7.inputs.nixpkgs.legacyPackages.${system};
      x = openxc7.packages.${system};
      python = pkgs.python312.withPackages (p: [
        x.fasm p.pyyaml p.textx p.simplejson p.intervaltree p.sortedcontainers
        # fasm's parser imports pyximport; the devShell's PYTHONPATH carries these
        p.cython p.distutils p.jaraco-envs p.jaraco-functools p.more-itertools p.packaging
      ]);
      gen = "${x.nextpnr}/share/nextpnr/himbaechel/uarch/xilinx/gen/xilinx_gen.py";
      envFile = pkgs.writeText "openxc7.env" ''
        export PATH=/opt/openxc7/bin
        export PRJXRAY_DB_DIR=${x.nextpnr}/share/nextpnr/external/prjxray-db
        export PYTHONPATH=${x.prjxray}/usr/share/python3
        export XILINX_GEN=${gen}
        export OPENXC7_PINS="toolchain-nix=092acc1e nextpnr=c68c1358 prjxray=3bfaec76 prjxray-db=517d66a3 nixpkgs=241313f4"
      '';
    in {
      packages.${system}.default = pkgs.buildEnv {
        name = "zm-openxc7";
        paths = [
          pkgs.yosys x.nextpnr x.prjxray python
          pkgs.bashInteractive pkgs.coreutils pkgs.which pkgs.gnumake pkgs.gnugrep pkgs.gnused pkgs.findutils
        ];
        postBuild = "mkdir -p $out/etc && cp ${envFile} $out/etc/openxc7.env";
      };
    };
}
