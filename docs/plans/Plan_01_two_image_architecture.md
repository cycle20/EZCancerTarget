# Plan 01 — Split into two Docker images: slim runtime + dev IDE

Status: **Proposed** · Created: 2026-07-16 · Target version: `cycle20/ezct:3.1.0`

## Goal

Replace the single `cycle20/ezct` image with **two purpose-built images that share one
`renv.lock`**:

1. **Runtime (slim)** — R + the project's package library only. Runs the data
   pipeline and the `tinytest` suite. Used in CI and production. No RStudio, no
   Quarto, no `esbuild`.
2. **Dev (IDE)** — the runtime environment plus RStudio Server (web IDE on port
   8787) for interactive development.

Both restore the **same pinned `renv.lock`**, so the dev environment reproduces the
runtime environment exactly, package-for-package.

## Motivation

- **Security / attack surface.** The current image is `rocker/tidyverse:4.6.1`,
  which bundles RStudio Server + Quarto. Quarto ships a Go-built `esbuild`
  (`/usr/lib/rstudio-server/bin/quarto/bin/tools/x86_64/esbuild`) that triggers
  Docker Scout CVE-2025-68121 (Go `crypto/tls`, stdlib `< 1.24.13`). The pipeline
  never uses Quarto/esbuild. Moving the pipeline onto `rocker/r-ver` removes that
  binary — and the whole RStudio/Quarto tool tree — from the production path.
- **Smaller, faster CI.** The slim image drops RStudio Server (hundreds of MB) and
  its transitive tooling. Test/pipeline runs pull and start a leaner image.
- **Clear separation of concerns.** Production/CI never ship an IDE or a web
  server; developers still get a full self-contained IDE when they want one.

## Current state (baseline)

- Single `Dockerfile` → `cycle20/ezct:3.0.0`, base `rocker/tidyverse:4.6.1`.
- `renv.lock` regenerated at R 4.6.1 with current packages (PPM `latest`); 63
  packages, restored as PPM binaries.
- `.dockerignore` excludes `.git`, `OUTPUT/`, logs, ad-hoc downloads.
- `exec/docker/run_rocker.bash` starts the image with RStudio Server on 8787.
- CI: `.github/workflows/tests.yml` (tinytest) and `clue.yml` (full pipeline) —
  both currently use `r-lib/actions/setup-renv`, **not** the Docker image.

## Verified facts (for implementers)

- `rocker/r-ver:4.6.1` default repo is `https://p3m.dev/cran/__linux__/noble/latest`
  with a matching `HTTPUserAgent`, so `renv::restore()` installs **binary** packages
  (fast, no compiler/cmake needed for `fs` etc.). Confirmed 2026-07-16.
- `rocker/r-ver:4.6.1` has **no `rstudio` user** — the slim image must create a
  non-root user itself.
- `rocker/r-ver:4.6.1` contains **no** `rstudio-server`, Quarto, or `esbuild`.

## Proposed architecture

Recommended: **two Dockerfiles that share `renv.lock`** (Pattern A). Simple, and
because both restore the identical pinned lockfile through PPM, the package
libraries are byte-for-byte equivalent — no drift.

```
renv.lock  (single source of truth)
│
├── Dockerfile            FROM rocker/r-ver:4.6.1     → cycle20/ezct:3.1.0        (slim runtime, default)
└── Dockerfile.dev        FROM rocker/tidyverse:4.6.1 → cycle20/ezct:3.1.0-dev    (RStudio IDE)
```

### Why not a layered build (dev = runtime + RStudio)?

A multi-stage `dev FROM runtime` would guarantee the dev image is a strict superset,
but installing RStudio Server onto `r-ver` means pulling rocker's
`install_rstudio.sh` / `install_pandoc.sh` scripts and their dependencies by hand —
more moving parts and network fetches for little gain, since `rocker/tidyverse`
already packages a tested RStudio + R 4.6.1. We keep the dev image on
`rocker/tidyverse` and rely on the shared `renv.lock` for parity. (Pattern B stays
available if strict image-subset parity ever becomes a hard requirement.)

## File-level changes

### 1. `Dockerfile` → slim runtime (was tidyverse-based)

- `FROM rocker/r-ver:4.6.1`.
- Install runtime/build system libs needed by the packages: `libssl-dev`,
  `libcurl4-openssl-dev`, `libxml2-dev` (same trio as today). **Verify** during the
  first build that `r-ver` isn't missing any lib the tidyverse base used to provide;
  add as needed (candidates if binaries want them at runtime: `libxml2`, `libssl3`,
  `libcurl4` are pulled in by the `-dev` packages already).
- Create a **non-root user** (e.g. `app`, uid 1000) and a home dir; set `HOME`,
  `RENV_PATHS_LIBRARY`, `RENV_PATHS_CACHE` under it (mirror current env vars).
- Copy `renv.lock`, `renv/`, `.Rprofile`; install `renv`; `renv::restore()`.
- Copy project source (`COPY --chown=app:app . .`).
- Default `CMD` runs the test suite (see §5), overridable to run pipeline stages.

### 2. `Dockerfile.dev` → RStudio IDE

- `FROM rocker/tidyverse:4.6.1` (keeps the `rstudio` user + IDE).
- Same renv restore block as today's `3.0.0` Dockerfile (reuses `renv.lock`).
- **Optional hardening:** `rm -rf /usr/lib/rstudio-server/bin/quarto/bin/tools/*/esbuild`
  to clear CVE-2025-68121 even in the dev image (safe — pipeline/tests don't use it;
  only affects interactive Quarto rendering).
- Keep RStudio entrypoint (`/init`, port 8787).

### 3. `.dockerignore`

- No change needed — already excludes VCS/output/cruft. Both Dockerfiles honor it.
- Confirm it doesn't exclude anything the slim image needs (it doesn't: `data/`,
  `R/`, `inst/`, `renv/` are kept).

### 4. Run helpers (`exec/docker/`)

- `run_rocker.bash` → repoint `IMAGE` to `cycle20/ezct:3.1.0-dev` (the IDE image).
- Add `run_pipeline.bash` (new) → runs the **slim** image non-interactively, e.g.
  `docker run --rm --network host cycle20/ezct:3.1.0 \
   R -e 'source("R/clue.R"); main()'` (and equivalents for `dataPatch.R`,
  `renderWebPage.R`).
- Add `run_tests.bash` (new) → `docker run --rm cycle20/ezct:3.1.0 \
   R -e 'tinytest::test_all()'` (or per-file, matching `AGENTS.md`).

### 5. Slim image entrypoint / default command

- Set `WORKDIR /app` and a default `CMD` that runs `tinytest::test_all()` so
  `docker run cycle20/ezct:3.1.0` self-tests, while pipeline stages are invoked by
  overriding the command (see run helpers). Note: tests must run from a dir where
  `.Rprofile` activates renv; use `R` (not `Rscript`, which skips `.Rprofile`), or
  set `R_PROFILE_USER`.

### 6. CI (`.github/workflows/`) — optional, follow-up

- `tests.yml`: optionally switch to `container: cycle20/ezct:3.1.0` (or build it in
  the job) instead of `setup-renv`, so CI exercises the exact runtime image.
- `clue.yml`: same, using the slim image for pipeline stages.
- Deferred: keep the current `setup-renv` flow working; image-based CI is a
  separate, testable change.

## Tagging & naming

| Image | Base | Tag | Consumers |
|-------|------|-----|-----------|
| Runtime (slim) | `rocker/r-ver:4.6.1` | `cycle20/ezct:3.1.0`, `:3.1`, `:latest` | CI, pipeline, prod |
| Dev (IDE) | `rocker/tidyverse:4.6.1` | `cycle20/ezct:3.1.0-dev` | local development |

Bump minor version to `3.1.0` since the runtime image's base OS layout changes
(tidyverse → r-ver). The `-dev` suffix keeps both in one Docker Hub repo.

## Build & verify steps

1. Build slim: `docker build -t cycle20/ezct:3.1.0 -f Dockerfile .`
2. Confirm cleanliness: `docker run --rm cycle20/ezct:3.1.0 bash -lc \
   'find / -name esbuild -o -name rserver 2>/dev/null | head'` → expect empty.
3. Verify packages load + run full `tinytest` suite in the slim image (target: same
   77 tests that pass on `3.0.0`).
4. Build dev: `docker build -t cycle20/ezct:3.1.0-dev -f Dockerfile.dev .`
5. Smoke-test dev: start via `run_rocker.bash`, open `http://localhost:8787`, log in,
   confirm the project library is active (`renv::status()`).
6. Compare libraries match: diff `installed.packages()[,Version]` between the two
   images → identical set/versions.
7. Re-scan both with Docker Scout: slim should no longer report CVE-2025-68121.

## Risks & open questions

- **Missing system libs on `r-ver`.** `r-ver` is more minimal than `tidyverse`.
  Some binary packages may need runtime shared libs not present. Mitigation: build
  early (step 1–3); add any missing `lib*` packages. Low risk — the three `-dev`
  libs cover openssl/curl/xml2, and RSQLite bundles SQLite.
- **`tinytest` in the slim image.** `tinytest` is in `renv.lock` (Suggests), so it
  restores into the library — good. Confirm it's present after restore (it is in
  `3.0.0`).
- **Non-root user creation.** Must set correct ownership on `/app`, the renv library,
  and cache dirs, or `renv::restore()` fails on permissions.
- **CI change is out of scope for the first cut.** Ship the two images first; wire
  CI to them as a separate PR to keep the blast radius small.
- **Kernel-headers CVEs (e.g. CVE-2026-53215) persist** in both images via
  `linux-libc-dev` (headers only, pulled by `libc6-dev`). Not addressed here — they
  are not runnable code and belong to the host kernel. Track separately / suppress.

## Rollout checklist

- [ ] Rename current `Dockerfile` logic into `Dockerfile.dev`; write new slim `Dockerfile`.
- [ ] Build + test slim image; fix any missing system libs.
- [ ] Build + smoke-test dev image (optionally strip `esbuild`).
- [ ] Verify identical package libraries across both images.
- [ ] Update `run_rocker.bash`; add `run_pipeline.bash`, `run_tests.bash`.
- [ ] Docker Scout re-scan of slim image is clean of CVE-2025-68121.
- [ ] Update `AGENTS.md` / `README.md` docker sections for the two-image workflow.
- [ ] (Follow-up) Point CI workflows at the slim image.
- [ ] Tag & push `3.1.0` and `3.1.0-dev`.
```
