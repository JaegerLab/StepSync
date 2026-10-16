# Regression checks

Use MATLAB with Signal Processing Toolbox, with the repository root on the path.

```matlab
addpath(pwd)
results = runtests('tests/test_analysis.m');
assertSuccess(results)
```

The numerical tests cover event boundaries and masks, independent thresholds,
STA time origins, duplicates and missing samples, recording boundaries and
random controls, smoothing limits, and sparse SLEAP frames.

Close StepSync before running the desktop integration test:

```matlab
results = runtests('tests/test_gait_ui.m');
assertSuccess(results)
```

This checks paw/trace switching, the mask editor without per-paw `.trace`,
preview versus commit, threshold persistence, all-false masks and invalidation
after a failed calculation. It is skipped without a desktop MATLAB session.

Manual checks with representative recordings are still required:

- Load single and consecutive RHD/RHS files; verify sample/channel counts and TTL rate.
- Switch to a recording without camera TTL; verify old triggers/processed data are gone.
- Load Open Ephys and explicitly select the camera TTL line when several exist.
- Load DLC CSV/HDF5/MAT and SLEAP files; inspect markers at known frames.
- Use a video whose encoded rate differs from acquisition rate; check first, consecutive,
  jumped-to and last frames, and playback speed.
- Save a session with a rate override, selected paw/trace, thresholds, time and zoom;
  reload over another session and after restarting; check all four viewers.
- Preview a pose correction, switch body part/settings and Save As; check source identity.

Validation performed in the editing environment: MISS_HIT parsed all 38 MATLAB
files without parser errors; 23 low-priority pre-existing name/value style notices
remain. `git diff --check` passed. One hundred randomized Python comparisons
validated the STA normalization formula against direct event-window averaging.
MATLAB/Octave were unavailable: the MATLAB tests have been written but not run.
