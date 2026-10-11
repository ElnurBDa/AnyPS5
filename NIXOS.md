# Building AnyPS5 on NixOS

These files make AnyPS5 build and run on NixOS, where the default toolchain can't
`-static`-link against glibc out of the box and generic Linux ELFs need an FHS
loader at runtime.

- **`shell.nix`** — a dev shell with the toolchain (cmake, ninja, gcc, pkg-config,
  python3) plus X11/XCB/Vulkan headers. Its shellHook builds one directory holding
  *both* glibc's shared objects and its static archives, searched first, so the
  static executables and the shared `.prx` libraries each resolve `-lc` correctly
  (this is the fix for the `R_X86_64_TPOFF32 ... local-exec is incompatible with
  -shared` error you hit otherwise).
- **`setup-runtime.sh`** — relink a decrypted PS5 ELF and assemble the runtime
  layout (`app.elf` + `libs/` + `app0/`). Guards against being handed an encrypted
  `.pkg`/PFS container instead of a clean ELF.
- **`unself.py`** — extract the clean inner ELF from a *fake-signed* homebrew SELF
  (e.g. ps5-doom's `eboot.bin`) so the relinker can accept it. Fake-signed homebrew
  is plaintext — this does not decrypt retail/encrypted content.

## Quick start
```sh
nix-shell

# relinker only (fast; runs the test suite):
cmake -S . -B build-relinker -G Ninja -DCMAKE_BUILD_TYPE=Release -DANYPS5_RELINKER_ONLY=ON -DBUILD_TESTING=ON
cmake --build build-relinker --parallel
ctest --test-dir build-relinker --output-on-failure

# full build (system .prx libraries + runtime):
git submodule update --init --recursive
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
cmake --build build --target libs --parallel
```

## Running a relinked title on NixOS
A relinked ELF expects the standard `/lib64/ld-linux-x86-64.so.2`, which NixOS
doesn't have, so launch it under `steam-run`:
```sh
./setup-runtime.sh source/input.elf out
cd out && steam-run ./app.elf      # ANYPS5_GPU=NVIDIA to force the discrete GPU
```

Worked example (public homebrew DOOM):
```sh
python3 unself.py PPSA99666/eboot.bin doom.elf   # fake-signed SELF -> clean ELF
cp PPSA99666/sce_module/libc.prx source/sce_module/   # (excluded at relink)
./setup-runtime.sh doom.elf out --exclude-sce-module libc.prx
```
