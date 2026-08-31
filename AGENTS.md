# AGENTS.md — permanent repository rules

Read this entire file every session. It is deliberately limited to durable agent guidance; project state and implementation detail belong in focused documentation.

## Authority and reading

- Current RTL, tests, and reports define implemented behavior; primary documentation and measured hardware define the target. Resolve disagreement explicitly.
- Read only the relevant authority: `Readme.md` for installation and user-facing behavior, `docs/development.md` for architecture and build mechanics, `docs/controller.md` for controller implementation, `docs/how-to-play.md` for game controls, `docs/beeper-status.md` for Studio II audio, `docs/analog-video.md` for direct video, and `roadmap.md` for future work.
- Keep mutable status, measurements, investigations, and release notes out of this file. Update the focused authority when a change makes it stale.

## Repository boundaries

- **Never modify `sys/`.** It is upstream MiSTer framework code. Fix integration in `Studio-II.sv` or core RTL.
- Preserve a compact, unified hardware model. Do not add parallel implementations, title-specific RTL, duplicated state, or speculative compatibility paths.
- Prefer hardware behavior over emulator convenience. Name the hardware, primary document, trace, or capture used for timing and geometry changes.
- Unknown behavior stays unknown. Do not infer controls or machine behavior from a similar title.
- CRCs identify exact file bytes. Verify the image, container, machine, selection sequence, keypad roles, and controls before adding a profile entry.
- Do not reorganize canonical paths or introduce dependencies on ignored/private reference material without an explicit repository-wide change.

## MiSTer and RTL invariants

- Quartus 17.0.x is the supported toolchain.
- `Studio-II.sv` is the `emu` top; keep MiSTer-facing policy there and machine behavior in `rtl/rcastudioii.sv` or the relevant device module.
- `bitmap_de`/core `video_de` is capture-only. Normal output DE comes from raster blanking through `video_mixer`.
- Preserve the separate machine-reset and video-reset policy: CLEAR, cartridge/firmware loads, and same-standard Apply keep raster timing live; PAL/NTSC changes are hard resets.
- Preserve instruction-boundary interrupt/DMA acceptance, held DMA requests, and the deliberate CDP1861 phase/EF timing.
- Keep Studio II signed beeper audio isolated from the Studio III programmable-tone path. Output controls such as mute must not reset or fork generator state.
- Use explicit widths and signedness. Keep counters/functions wide enough for their declared maxima; do not rely on implicit truncation or widening.
- Write synthesizable RAM in an inference-safe form. After any RAM-port or read/write-mode change, the Quartus map report must still show block RAM.
- Keep `files.qip` and every Verilator source list synchronized when live RTL files change. `Studio-II.qsf` may be regenerated; do not use it as the source list or stage incidental churn.
- Verilator output may be stale after RTL edits; clean the relevant object directory before trusting a suspicious rebuild.
- Follow the existing RTL formatting and module conventions. Avoid unrelated cleanup in functional changes.

## Work and approval rules

- Inspect Git status before editing and before handoff. Preserve user changes, generated captures, firmware, and release artifacts; never delete or overwrite them as cleanup.
- Do not commit, stash, create/switch/delete branches or tags, rewrite history, push, change a PR, or create a release unless the user explicitly asks for that action.
- Never push from this repository. A push may trigger an automated build or distribution; prepare the local commit and leave the push to the user.
- Treat `releases/` as a live distribution boundary: adding or replacing a file there can send it to users through `update_all`. Never change a release artifact unless the user explicitly requests that exact publication change, and always leave publication to the user.
- Never run Quartus synthesis. Give the user the exact supported command and review the resulting reports they provide.
- Do not run Verilator builds, hardware regressions, or other long jobs unless the user explicitly asks. Prefer the exact command plus expected result; quick static checks are allowed.
- Substantial additions use a dedicated review branch after user approval. Treat `main` as release-producing.
- Before any permitted remote Git action, review the diff and untracked files and obtain explicit approval.

## Change discipline

- Make the smallest change that completely solves the problem. Words and abstractions are maintenance liabilities too.
- Tests must target the changed failure class; never present emulator agreement as complete hardware accuracy or simulation success as proof of FPGA RAM inference.
- Keep code comments terse: explain only non-obvious operation, constraints, rationale, or hardware-source correspondence. Do not restate code or narrate ordinary bug history, failed approaches, or fix chronology; put those in focused docs and distill only recurring high-risk traps back into code.
- Finish by reviewing the complete diff, reporting what was and was not verified, and identifying any user-run build, Quartus, or hardware check still required.
