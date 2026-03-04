# top_asm

A clone of the macOS `top` command written entirely in ARM64 (AArch64) assembly for Apple Silicon.

## What it does

Displays a live, auto-refreshing system monitor in your terminal (similar to `top`), showing:

- **Process summary** — total, running, and sleeping process counts
- **CPU usage** — user, system, and idle percentages (computed from tick deltas)
- **Physical memory** — used and free in MB (via Mach `vm_statistics64`)
- **Per-process table** — top 20 processes sorted by CPU usage, with PID, CPU%, resident memory, state, and command name

Updates every 2 seconds. Running processes are highlighted green; non-standard states are yellow.

## How it works

The entire program is a single `top.s` assembly file that directly invokes macOS kernel and Mach APIs:

- `mach_host_self` / `host_statistics` / `host_statistics64` for CPU and VM stats
- `sysctlbyname` for total physical memory
- `proc_listallpids` / `proc_pidinfo` for per-process information
- Tracks per-process CPU time deltas to compute CPU% between samples
- Insertion sort on CPU usage for the display ranking

No libc is used beyond `printf`, `usleep`, and `fflush`. All struct offsets, system constants, and buffer management are handled manually in assembly.

## Requirements

- Apple Silicon Mac (ARM64)
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```
make
./top_asm
```

## Utilities

`verify_offsets.c` prints the struct sizes and field offsets used by `top.s`, useful for verifying the hardcoded constants match your SDK version:

```
make verify
```

## Clean

```
make clean
```
