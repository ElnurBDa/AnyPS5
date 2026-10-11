# NixOS-friendly build environment for AnyPS5.
#
#   nix-shell            # enter the dev shell (auto-picks this file)
#   nix-shell --run '…'  # run one command inside it
#
# AnyPS5 links its executables fully static (-static -static-libgcc
# -static-libstdc++, see CMakeLists.txt) while also building shared system
# libraries (*.prx). On NixOS that combination needs care: static exes need
# glibc's .a archives, shared libs need glibc's .so — and if the static
# archives are found first for a -shared link you get
#   R_X86_64_TPOFF32 against `tcache' ... local-exec is incompatible with -shared
# The shellHook below builds one directory holding BOTH the shared libs and the
# static archives and puts it first on the linker path, so each link kind
# resolves -lc correctly no matter the cc-wrapper's search order.
{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  name = "anyps5-build";

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
    pkgs.git
    pkgs.python3 # relinker regression tests + import_audit.py
  ];

  # Libraries whose lib/ dirs land on the linker path (for the FULL build + run).
  buildInputs = [
    pkgs.libx11 # SDL2 is built with SDL_X11=ON
    pkgs.libxext
    pkgs.libxcb # SDL's bundled vulkan.h pulls in <xcb/xcb.h> for the Vulkan/X11 surface
    pkgs.vulkan-loader # libvulkan.so.1, to actually run a ported title
    pkgs.vulkan-headers
  ];

  shellHook = ''
    # One dir with BOTH glibc's shared objects and its static archives, searched
    # first: -static exes resolve -lc -> libc.a, -shared .prx -> libc.so.
    export ANYPS5_LIBC_DIR="''${TMPDIR:-/tmp}/anyps5-libc"
    mkdir -p "$ANYPS5_LIBC_DIR"
    ln -sfn ${pkgs.glibc}/lib/*        "$ANYPS5_LIBC_DIR"/ 2>/dev/null || true
    ln -sfn ${pkgs.glibc.static}/lib/* "$ANYPS5_LIBC_DIR"/ 2>/dev/null || true
    export NIX_LDFLAGS="-L$ANYPS5_LIBC_DIR $NIX_LDFLAGS"
    echo "anyps5-build shell ready: gcc $(gcc -dumpversion), cmake $(cmake --version | head -1 | awk '{print $3}'), ninja $(ninja --version)"
  '';
}
