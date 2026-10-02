# openXC7 (yosys + nextpnr-xilinx + Project X-Ray) for fpga/tools/openxc7.sh.
# openXC7 publishes no Docker image; its own container recipe is
# toolchain-nix/container/Containerfile (nixos/nix + `nix develop`, unpinned).
# This is that recipe pinned: the base by digest, the tools by flake.nix +
# flake.lock (toolchain-nix 092acc1e: nextpnr c68c1358, prjxray 3bfaec76,
# prjxray-db 517d66a3, nixpkgs 241313f4 for yosys).
#
#   fpga/tools/openxc7.sh image     builds it as zm-openxc7:<flake.lock hash>
FROM nixos/nix:2.31.2@sha256:29fc5fe207f159ceb0143c25c19c774062fee02ce5eda118f3067547b3054894

# cores/max-jobs: the box is shared (15 GB), nextpnr's C++ is the peak.
RUN printf 'experimental-features = nix-command flakes\ncores = 4\nmax-jobs = 2\n' >> /etc/nix/nix.conf

COPY flake.nix flake.lock /src/
# One layer: build, then drop the compilers and sources the closure doesn't need.
RUN nix build path:/src -o /opt/openxc7 \
    && nix-collect-garbage -d \
    && /opt/openxc7/bin/yosys -V && /opt/openxc7/bin/nextpnr-himbaechel --version

# GC above also dropped the base image's coreutils, so nothing here runs a shell.
COPY --chmod=755 entry.sh /opt/entry.sh
ENTRYPOINT ["/opt/entry.sh"]
CMD ["bash"]
