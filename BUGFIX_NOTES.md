# Review fixes (based on 88e5507)

## Preserved behavior

- `maskTemp` is display-only. Detection and STA events use committed `mask`.
  Generate Mask clears the preview before broadcasting committed data.
- Without camera TTLs, frame 1 remains at `1/frameRate`. The subsequent timing review below adds measured camera timing when available.
- Only the selected paw/trace is analyzed. No per-paw `.trace` vector is required.
- Manual thresholds persist across refreshes. Automatic thresholds use the full
  finite trace, consistently in display and detection, as in the prior plot behavior.

## Original findings

| # | Resolution |
|---|---|
| 1 | RHS field normalization was already fixed upstream; concatenation now filters input files and rejects incompatible channel/rate layouts. |
| 2 | Qualified HDF5 helper; matched MAT function name to its renamed file. |
| 3 | Restore timing settings, broadcast updates, restore UI values in dependency order. |
| 4 | Replace recording-specific EMG state rather than retaining triggers, processed arrays or maps. |
| 5 | Selected-paw calculation retained; consistent automatic threshold, valid-result guard and selection identity added. |
| 6 | Upstream threshold persistence retained; interval changes no longer accidentally save an automatic threshold as manual. |
| 7 | Onset/offset use the actual clipped search indices; searches stop at missing/masked samples. |
| 8 | Preview/calculation mask difference is intentional, not a defect. Fixed stale/full-empty trace display and removed event plotting's dependency on masked plot YData. |
| 9 | Use gait timestamps for rules; interpolate timestamped speed onto that grid, treating uncovered time as excluded. Untimed speed must match sample count. |
| 10 | Track video frame identity independently of encoded `CurrentTime`. |
| 11 | Map STA events relative to actual EMG origin; retain time-zero samples; reject uneven/gapped timestamps instead of silently misaligning them. |
| 12 | Normalize each STA lag by its contributing finite samples, including controls; unavailable samples are not zeros. |
| 13 | Accumulate duplicate events; reject empty observed event sets; shuffle the filtered event times. |
| 14 | Bind pose previews to source body part and parameters; invalidate after raw marker edits. |
| 15 | Replace imported gait source state, clearing old paws, masks and histories. |
| 16 | Guard time-to-frame indexing at zero and beyond shorter pose recordings; hide out-of-range video markers. |
| 17 | Choose a camera digital channel when several exist; fall back from absent/invalid TTL rates. |
| 18 | Use the same origin for analog/TTL time; choose a camera TTL line. Upstream Open Ephys source was inspected for field names. |
| 19 | Close/reset existing modules when replacing a session; empty viewers tolerate data notifications. |
| 20 | Centralize validated rate edits and notify all viewers. |
| 21 | Removed the unused legacy gait-analysis function. Correction to original report: `valley` itself remained in frame units; the alleged fractional stride indexing was not a defect. |
| 22 | Alternative correction routines were already deleted upstream; not reintroduced. |
| 23 | Removed the stale head-fixed prototype after confirming it is outside the application call chain. Head-fixed analysis remains in the active GUI. |
| 24 | Reconstruct SLEAP frame gaps; select one track rather than flattening tracks. |
| 25 | Superseded by the playback correction below: advance by the selected frame step, without wall-clock catch-up. |
| 26 | Validate positive finite rate overrides; use valid TTL/video fallback. |
| 27 | Handle full-length/oversized smoothing windows and localize missing samples instead of poisoning the entire tail. |
| 28 | Removed the unused Kalman smoother and its test. |

## New refactor conflicts

The mask editor now derives shape from `gait.t`. Steps are computed into a local
result, published only on success, stamped with the selected paw/trace, and guarded
before plotting, video opacity updates or STA. A failed recalculation hides old
markers and invalidates the old result. First import constructs time from raw
coordinates rather than a not-yet-populated local `paw.x` copy.

## Validation limits

See `tests/README.md`. Static parsing and formula checks pass. MATLAB tests,
graphics behavior and actual recording readers still need execution in the lab's
MATLAB environment before merging into the main branch or interpreting changed
scientific outputs. In particular, STA boundary normalization intentionally changes
edge results, and imported-speed interpolation changes previously misaligned masks.

## Unused-file cleanup

At the owner's request, removed all eight files outside the application call chain:

- `+EMG/kalman_smooth.m`
- `+EMG/preview.m`
- `+GAIT/gait_analysis.m`
- `+GAIT/gait_analysis_headfix.m`
- `+VIDEO/hist.m`
- `+shared/dev_reload_session.m`
- `+shared/find_index.m`
- `+shared/nan_index.m`

Removed tests targeting the deleted head-fixed prototype and Kalman smoother.

## Timing and independent-review follow-up

- Camera TTL timestamps now supply a shared frame clock to video, pose, gait,
  masks and STA. A count difference of one is treated as an unmatched final
  record; an unmatched frame has no event timestamp. Larger differences error.
  Legacy session cursor, zoom and rule times are migrated once; saved STA results
  require recalculation and generate a warning.
- Global STA uses the standard error based on contributing events at each lag,
  independent of control repetitions. This is an approximate SEM band: correlated
  or overlapping events can reduce the effective sample count. Whole-session
  random-time controls and local dither retain their intended sampling domains.
- Speed onset/offset uses an internal resting-noise estimate, with no extra GUI
  parameter. A smoothed speed histogram identifies sustained low-motion windows;
  the 75th percentile of original speed within their interiors sets near-zero.
  No identifiable rest means no onset/offset estimate. X/Y expose neither event.
  The heuristic needs validation on representative recordings.
- Corrected DLC Fix filename case, trace click editing, graded likelihoods and
  CSV scorer/column handling. CSV export remains a helper, without a new GUI.
- Initialized TTL summaries before notifications, preserved channel-map labels,
  guarded empty Refresh actions, and separated mask preview notifications.
- Gapped DLC speed can be imported without an open pose viewer; frame-indexed
  speed scales with current calibration. Mask smoothing requires a positive window.
- Binary Open Ephys streams use per-channel bit-volts metadata for units.
  Multiple recordings/streams require selection. Non-binary recordings retain
  explicitly labeled counts with a warning rather than guessed scaling.
- Added regression coverage for timing, migration, statistics, resting thresholds,
  units, CSV, likelihoods and GUI guards. Static parsing passes; MATLAB execution
  remains required before merging or relying on changed scientific outputs.

## Frame-step playback correction

Restored the intended playback contract after owner testing: each timer callback
advances from the displayed frame by the selected PlayStep (1/2/4/8/16).
A fixed-spacing timer waits for the callback to complete, so slow rendering only
slows playback. No tic/toc or frame-rate multiplier is used. The final step clamps
to the last timestamped frame and stops. TTL timestamps still synchronize viewers.
Static parsing passes; MATLAB video/GUI playback must be verified manually.
