# Stream URL deciphering (n + signatureCipher) — on-device, all platforms

Replaces the old simulator-only `YouTubeNDescrambler` (Deno + yt-dlp via `posix_spawn`),
which was removed in Nov 2026 along with its dead call sites.

## Problem

Clients that use YouTube's web player JS (WEB, MWEB, WEB_EMBEDDED_PLAYER, WEB_CREATOR,
TVHTML5) return stream URLs that need player-JS transforms:

- **`n`** — throttling token, as `&n=` on progressive/adaptive URLs and `/n/…/` in HLS
  manifest paths. Unsolved → googlevideo returns **403**.
- **`signatureCipher`** — formats with no `url`, only `s` + `sp` + `url`. Without
  deciphering, the format is unusable (previously dropped).

JS-less clients (iOS, Android, Android VR, visionOS) must **not** be transformed.

## Solution

- `YouTubeJSSolver` (`SmartTubeIOS/Services`) runs yt-dlp's EJS solver
  (`Resources/yt.solver.{lib,core}.min.js`, ejs 0.8.0) in **JavaScriptCore**. Works on tvOS.
  - Player version from `iframe_api` (fallback: homepage); `base.js` downloaded once per version.
  - Preprocessed player cached in `Caches/ejs-solver-<ejs>/<version>.pre.js` (+ `.sts`).
  - Cold preprocess ≈1.1 s on a desktop CPU without JIT; cached solves ≈20 ms.
  - Installed at launch via `YouTubeJSSolver.install()` (registers in
    `StreamURLDecipherRegistry` and warms in the background).
- `InnerTubeAPI.parsePlayerInfo(usesJSPlayer:)` batches all `n`/`sig` challenges and rewrites
  format URLs through `StreamURLRewriter` (Core, pure, unit-tested).
- `fetchSignatureTimestampIfNeeded` prefers the solver's player STS so ciphers match.
- HLS: `PlayerInfo.hlsRequiresNTransform` → `PlaybackQualityManager.makeHLSAsset` proxies the
  master through `YTHLSProxyLoader(solvesNChallenges:)`. The master is left untouched; every
  *media* playlist (segment list) has its `/n/…/` solved before AVPlayer sees it. The manifest
  server echoes whatever n it is sent into segment URLs, so solving at the media-playlist level
  is stateless and can never double-transform (solve(solve(n)) → 403).

## Verified (2026-11-15, player fad7e4e9, residential ISP connection)

- jit-less JSC output == Node output for n and sig.
- MWEB itag 18 (progressive): original n → 403, solved n → 206. Reproducible.
- WEB HLS segments: original n → 403 in every run. Solved n → 200 (≈100 KB) in early runs,
  then 403 for every variant/strategy after a few dozen rapid test requests — likely
  short-term throttling of the test IP or `rqh` PO-token enforcement, not n. Re-verify on
  device after a cool-down.

## Updating the solver

Replace both `yt.solver.*.min.js` from https://github.com/yt-dlp/ejs/releases and bump
`YouTubeJSSolver.bundledEJSVersion` so stale preprocessed caches are ignored.
