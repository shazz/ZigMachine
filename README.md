# ZigMachine

## Specs


## Build

The default (and only) target for this example is `wasm32-freestanding-musl`.

To build the wasm module, run:

```shell
$ zig build bootloader -Drelease=true
```

Note: `build.zig` specifies various wasm-ld parameters. For example, it sets the initial memory size
and maximum size to be xxx pages, where each page consists of 64kB. Use the `--verbose` flag to see the complete list of flags the build uses.

## Run

Start up the server in this repository's directory:

```shell
python3 -m http.server
```

Go to your favorite browser and type to the URL `localhost:8000`.
