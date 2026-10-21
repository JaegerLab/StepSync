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
last module window closes, and the remembered dialog folder. `test_sessions`
writes session files and reads them back (selected modules only, format
marker `fileFormat = 'StepSync session'`, `formatVersion = 3`) and checks that
other files, older and newer formats are rejected. `test_emg` covers the EMG
data types (Raw, Processed 1..N, renumbering after delete, `has('emg')` with
processed data only, frame timing from the trigger without data), the EMG
`.mat` file (selected types, processed-only loading, rejected files) and the
achieved sample rate after down sampling.

Close StepSync before running the desktop integration test:

```matlab
results = runtests('tests/test_gait_ui.m');
assertSuccess(results)
```

This checks paw/trace switching, the mask editor without per-paw `.trace`,
preview versus commit, threshold persistence, all-false masks and invalidation
after a failed calculation, and the menu bar: launcher closing, Window menu
checkmarks and sub-windows, and Exit all resetting the session; and that
restoring a session replaces all module windows and brings back window
positions, widget values, data, frame rate, time and zoom; and that EMG
pre-processing adds Processed types from the selected source (with the
achieved rate and `parameters.Source`), the delete button is off while the
pre-process window is open, and deleting every type keeps the trigger. The viewers
are closed with `shared.exit_all(false)`, which skips the close confirmations.
It is skipped without a desktop MATLAB session.

Manual checks of the menu bar and windows:

- The launcher closes when a module opens from a button, the Window menu or
  Load session; running `StepSync` while modules are open raises them instead.
- Window menu: checkmarks follow open modules; open sub-windows are listed,
  indented, under their module and disappear when closed; Bring All to Top
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
  Close, Ctrl+I/E/D/G open or raise Video/EMG/DLC/Gait, Ctrl+A Open All,
  Ctrl+T Bring All to Top.

Manual checks with representative recordings are still required:

- Load single and consecutive RHD/RHS files; verify sample/channel counts and TTL rate.
- Switch to a recording without camera TTL; verify old triggers/processed data are gone.
- Load Open Ephys and explicitly select the camera TTL line when several exist.
- Load DLC CSV/HDF5/MAT and SLEAP files; inspect markers at known frames.
- Use a video whose encoded rate differs from acquisition rate; check first, consecutive,
  jumped-to and last frames, and playback speed.
- Save a session with a rate override, selected paw/trace, thresholds, time and zoom;
  reload over another session and after restarting; check all four viewers.
- Save session lists the open modules, all selected; save only some and check
  that loading reopens just those. With no module open it shows an alert.
- Load session asks once when module windows are open, not from the launcher;
  a non-session or old session file shows an alert and closes nothing.

Manual checks of EMG:

- Pre-process Raw, then pre-process Processed 1: the preview (yellow)
  overlays the selected source; the dropdown lists Raw, Processed 1, 2.
- The ✕ button asks before deleting the selected type (also Raw); remaining
  processed types are renumbered; with everything deleted the dropdown shows
  "no data", plots disappear, and the video still uses the trigger timing.
- Save with several types offers a selection; the title switches to the saved
  file. Choosing the `.mat` the EMG was opened from is refused.
- Open .mat lists raw/processed with sizes; open only a processed type and
  check plots, channel map/sort, STA and zoom without raw data.
- Without open-ephys-matlab-tools on the path, opening an Open Ephys folder
  prints a message, shows a message box with the install link, and stops.
- Preview a pose correction, switch body part/settings and Save As; check source identity.

Validation performed in the editing environment: MISS_HIT parsed all 38 MATLAB
files without parser errors; 23 low-priority pre-existing name/value style notices
remain. `git diff --check` passed. One hundred randomized Python comparisons
validated the STA normalization formula against direct event-window averaging.
MATLAB/Octave were unavailable: the MATLAB tests have been written but not run.
