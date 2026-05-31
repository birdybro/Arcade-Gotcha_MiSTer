# MiSTer Context Bundle — Index

> Bundle version: 2026-05-18
> Target hardware: DE10-Nano + MiSTer add-on boards
> Target framework: MiSTer-devel `Template_MiSTer` family

## What this bundle is

A drop-in reference for an AI coding agent implementing or debugging MiSTer FPGA cores. Every claim is sourced from a pinned commit of an official `MiSTer-devel` repository. The bundle does not replace reading the RTL — it pins down the contracts and conventions so the agent doesn't have to discover them by trial and error.

## How to use this bundle

### For a fresh task ("orient a new core")

Load:
1. `00-INDEX.md` (this file)
2. `01-glossary.md`
3. `10-emu-top-level.md`
4. `11-conf-str.md`
5. `20-hps-io-overview.md`
6. `91-porting-checklist.md`

That set fits in a small context window and unlocks basic core scaffolding.

### For a specific question, load the topic doc plus its `Load with:` neighbors

Each topic doc declares its neighbors in its header. Follow them.

### For deep debugging

Load `02-source-map.md` to find the upstream proof of any specific behavior, then read the cited archive lines directly.

## Reading order summary

| Range | Section |
| --- | --- |
| `00-02` | Entry layer: this index, glossary, citation hub |
| `10-12` | Top-level: `emu` module, `CONF_STR` grammar, clocks/resets/PLLs |
| `20-23` | HPS bridge: hps_io overview, ioctl/download, mount/SD, OSD+input |
| `30-33` | Memory: SDRAM, DDRAM, ROM/save flows, BRAM (on-chip M10K) |
| `40 / 40a / 41` | Video (emu boundary), video pipeline (framework `sys/` modules), audio |
| `50-53` | Build, simulate, MRA/arcade, cross-core patterns |
| `90-91` | Anti-patterns, porting checklist |

## Claim labels

Every factual sentence in §2, §3, §6 of each topic doc carries one of:

- **`[C]` Framework contract** — required by `sys/` or `Main_MiSTer`. Violation breaks the core.
- **`[V]` Core convention** — common pattern across cores, not strictly required by the framework.
- **`[O]` Observed in core X** — present in a specific core at a specific commit. Names the core.
- **`[I]` Inference** — synthesized from multiple sources. Treat with care; double-check against current source.

## Excerpt format

Code excerpts are preceded by a comment line giving archive path, line range, and commit hash:

````
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:421-450 @ f35083f3b40d
```verilog
...
```
````

## Provenance (pinned commits)

| Repository | Commit |
| --- | --- |
| `Template_MiSTer` | `f35083f3b40d` |
| `Main_MiSTer` | `136737b4bed4` |
| `MkDocs_MiSTer` | `9033bd292fdc` |
| `Hardware_MiSTer` | `bbd361962005` |
| `Distribution_MiSTer` | `beb65fea786d` |
| `Menu_MiSTer` | `b0a2b9298d7a` |

To re-pin: `python3 scripts/fetch_mister_sources.py --profile starter` and re-derive citations.

## Scope (in / out)

**In scope:** DE10-Nano hardware; `Template_MiSTer` family `emu`/`sys/` framework; `Main_MiSTer` HPS-side bridge; CONF_STR; hps_io; SDRAM; DDRAM; video pipeline (CLK_VIDEO through HDMI); audio; OSD; input; clocks/PLLs; build (Quartus 17.0.x and 13.x); simulation; MRA/arcade; cross-core patterns.

**Out of scope:** DE10-Standard or other board variants; Linux/userspace beyond the HPS↔FPGA interface; u-boot/bootloader; distribution tooling; per-core game-specific documentation.
