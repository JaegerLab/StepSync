# Regression checks

Use MATLAB with Signal Processing Toolbox, with the repository root on the path.

```matlab
addpath(pwd)
results = runtests('tests');
assertSuccess(results)
```

From a shell, change folder inside MATLAB: a `startup.m` that changes the
folder overrides `-sd`, and `runtests('tests')` then finds no tests and still
succeeds.

```
matlab -batch "cd('<repository root>'); addpath(pwd); results = runtests('tests'); assertSuccess(results)"
```

The numerical tests cover event boundaries and masks, independent thresholds,
STA time origins, duplicates and missing samples, recording boundaries and
random controls, smoothing limits, and sparse SLEAP frames. `test_windows`
covers sub-window placement on multiple monitors, the session reset after the
last module window closes, and the remembered dialog folder.

Close StepSync before running the desktop integration test:

```matlab
results = runtests('tests/test_gait_ui.m');
assertSuccess(results)
```

This checks paw/trace switching, the mask editor without per-paw `.trace`,
preview versus commit, threshold persistence, all-false masks and invalidation
after a failed calculation, and the menu bar: launcher closing, Window menu
checkmarks and sub-windows, and Exit all resetting the session. The viewers
are closed with `shared.exit_all(false)`, which skips the close confirmations.
It is skipped without a desktop MATLAB session.

Manual checks of the menu bar and windows:

- The launcher closes when a module opens from a button, the Window menu or
  Load session; running `StepSync` while modules are open raises them instead.
- Window menu: checkmarks follow open modules; open sub-windows are listed,
  indented, under their module and disappear when closed; Bring All to Front
  leaves the invoking window on top.
- Close and the window's X ask before closing a module window; sub-windows
  close without asking; Exit all asks once.
- After Exit all, or after closing the last module window, a new `StepSync`
  has no leftover frame rate, time, zoom or path.
- Sub-windows opened near a screen edge or on a second monitor are fully
  visible, title bar (and the STA menu bar) included.
- Titles show the opened file, also after Load session; file dialogs start in
  the folder of the last file opened.
- Shortcuts in every window with a menu: Ctrl+O Open, Ctrl+S Save, Ctrl+W
  Close, Ctrl+V/E/D/G open or raise Video/EMG/DLC/Gait, Ctrl+A Open All.
  Check that Ctrl+V and Ctrl+A still paste and select text in edit fields.

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
