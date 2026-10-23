# Command-line functions

The viewers are built on a few functions that also work on their own, from the
command line or in your own scripts. They take plain arrays, need no open
window and no session, and return plain MATLAB data.

| Function | Purpose |
|---|---|
| [`EMG.emg_prep`](#emgemg_prep) | High-pass filter, rectify, smooth and down-sample EMG |
| [`DLC.dlc_fix`](#dlcdlc_fix) | Correct jumps (mislabels) in a pose trajectory |
| [`GAIT.detect_steps`](#gaitdetect_steps) | Find step events in a paw trace |
| [`GAIT.sta`](#gaitsta) | Step-triggered average with a chance-level control |
| [`GAIT.plot_sta`](#gaitplot_sta) | Plot a result of `GAIT.sta` |

Add the StepSync folder (the one that contains `StepSync.m`) to the path; the
functions are in the packages `+EMG`, `+DLC` and `+GAIT`, so they are called
with the package prefix. `help DLC.dlc_fix` and so on print the full help.

## A complete example

```matlab
addpath('C:\path\to\StepSync')

% EMG: read a recording, rectify and down-sample channel 3 to 1 kHz
rec = EMG.emg_read('D:\data\mouse1\emg');
opt = struct('HighPassFreq', 50, 'Rectify', true, 'DownSampleRate', 1000);
[env, t_emg] = EMG.emg_prep(rec.analog_data(:,3), rec.t, opt, rec.sample_rate);

% Pose: read DeepLabCut output and fix the right hind paw
T = DLC.read_dlc('D:\data\mouse1\video1DLC.csv');
[x, y] = DLC.dlc_fix(T.RH_x, T.RH_y);

% Gait: speed in cm/s, then movement onsets
fps = 200; px_per_cm = 20;                       % your camera
speed = GAIT.smooth_speed(x, y, 3) * fps / px_per_cm;
t_video = (0:numel(speed)-1)' / fps;             % or frame times from the TTL
steps = GAIT.detect_steps(speed, true(size(speed)), 10, round(0.1*fps), 2);

% STA of the EMG envelope around the onsets
result = GAIT.sta(env, t_emg, t_video(steps.onset), 'max_lag', 0.3);
GAIT.plot_sta(result);
```

The times passed to `GAIT.sta` must be on the EMG clock. In the GUI, video
frames are placed on that clock from the camera TTL pulses (see
[Timing and synchronization](synchronization.md)); in a script you supply the
frame times yourself.

## EMG.emg_prep

```matlab
[new_data, new_t, new_fs] = EMG.emg_prep(data, t, options)
[new_data, new_t, new_fs] = EMG.emg_prep(data, t, options, fs)
```

Preprocesses EMG in a fixed order: high-pass filter, rectify, smooth and
down-sample. Every step is optional and is switched on by a field of `options`.
This is what **Pre-Process** in the [EMG viewer](emg.md) runs.

| Input | Description |
|---|---|
| `data` | Samples × channels. Each column is processed independently |
| `t` | Time of each sample (s), a vector with one value per row of `data` |
| `options` | Struct; leave a field out to skip that step (see below) |
| `fs` | Sample rate (Hz). Default: `1/mean(diff(t))` |

| `options` field | Effect |
|---|---|
| `HighPassFreq` | High-pass filter at this frequency (Hz): 4th-order IIR (Butterworth) |
| `FiltFilt` | `true`: zero-phase filtering with `filtfilt`. `false` (default): causal `filter` |
| `Rectify` | `true`: absolute value. Default `false` |
| `DownSampleRate` | Target rate (Hz). The data are smoothed with a moving window of 2.5 × the down-sampling factor, then every *k*-th sample is kept, with *k* = `round(fs/DownSampleRate)` |

| Output | Description |
|---|---|
| `new_data` | Processed data |
| `new_t` | Time of each output sample |
| `new_fs` | Achieved sample rate, `fs/k`, which can differ from `DownSampleRate` when `fs` is not a multiple of it |

Samples at negative time (before the recording started) are dropped. A progress
bar is shown while the function runs.

```matlab
% envelope at ~500 Hz, zero-phase filter
opt = struct('HighPassFreq', 30, 'FiltFilt', true, 'Rectify', true, 'DownSampleRate', 500);
[env, t2, fs2] = EMG.emg_prep(raw, t, opt, 30000);
```

## DLC.dlc_fix

```matlab
[x_fix, y_fix, mask, seg] = DLC.dlc_fix(x, y)
[x_fix, y_fix, mask, seg] = DLC.dlc_fix(x, y, jump_thresh, win_width)
[x_fix, y_fix, mask, seg] = DLC.dlc_fix(x, y, jump_thresh, win_width, mask_or_seg)
[...] = DLC.dlc_fix(..., visualize)
```

Corrects short tracking errors in one body part's trajectory. The trace is cut
into segments at jumps larger than `jump_thresh`. Segments at least
`win_width` frames long are trusted seeds, and the remaining segments are
accepted or rejected by comparing them with an interpolation through the
trusted frames. The rejected frames are then replaced by that interpolation.
The algorithm is described in [Pose viewer and correction](pose.md). This is
what **DLC Fix** runs.

| Input | Description |
|---|---|
| `x`, `y` | Coordinates of one body part, in pixels (vectors of equal length) |
| `jump_thresh` | Jump threshold (pixels). `[]` or omitted: estimated by `DLC.auto_jump_threshold` |
| `win_width` | Seed width (frames). `[]` or omitted: estimated by `DLC.auto_window_width` |
| `mask_or_seg` | Optional. A logical vector (one value per frame) marks frames you already know to be good (`true`) or bad (`false`): good runs become seeds, bad runs are rejected, and nothing is propagated. A segment structure (`seg` from an earlier call, possibly edited) re-runs the algorithm only around the edited segments |
| `visualize` | `true` to plot the result, with the same layers and styles as the correction overlay in the DLC viewer (`DLC.fix_style`), plus the suggested fix at each conflict. Default `false` |

| Output | Description |
|---|---|
| `x_fix`, `y_fix` | Corrected trajectory: a pchip interpolation through the good frames. Before the first and after the last good frame the nearest good value is held |
| `mask` | Logical, `true` for frames in good segments |
| `seg` | Segment structure: start, stop, length and flag of each segment, the jumps, and conflicts with suggested fixes. See `help DLC.dlc_seg_build` |

Segment flags in `seg.flag`: 2 seed, 1 good, 0 undetermined, −1 bad,
−2 questionable, −3 rejected. `DLC.seg_likelihood(seg)` turns them into a
per-frame likelihood, as used when the GUI saves a fixed body part.

```matlab
T = DLC.read_dlc('video1DLC.csv');            % columns <bodypart>_x/_y/_likelihood
[xf, yf, good, seg] = DLC.dlc_fix(T.nose_x, T.nose_y, 20, 60, [], true);

% use likelihood as prior knowledge instead of propagation
[xf, yf] = DLC.dlc_fix(T.nose_x, T.nose_y, 20, [], T.nose_likelihood > 0.9);

% mark segment 12 as good by hand, then update only around it
seg.flag(12) = 2; seg.is_new(12) = true;
[xf, yf, good, seg] = DLC.dlc_fix(T.nose_x, T.nose_y, [], [], seg);
```

When a segment structure is passed, `jump_thresh` and `win_width` default to
the values stored in it. To add or remove a jump in `seg`, use
`DLC.dlc_seg_toggle_jump`.

## GAIT.detect_steps

```matlab
steps = GAIT.detect_steps(trace, mask, threshold, minInterval)
steps = GAIT.detect_steps(trace, mask, threshold, minInterval, nearZero)
```

Finds step events in one paw trace (x, y or speed). The event definitions are
those of the [Gait viewer](gait.md#step-events).

| Input | Description |
|---|---|
| `trace` | Paw trace, one value per frame |
| `mask` | Logical, `false` for frames to exclude. Use `true(size(trace))` for no mask |
| `threshold` | Threshold in the units of `trace` |
| `minInterval` | Minimum distance between events, in **frames** (a positive integer). Also the search range for onset and offset |
| `nearZero` | Speed treated as rest, for onset and offset. Default `NaN` (no onsets or offsets). `GAIT.auto_rest_threshold(speed, fps)` estimates it as the Gait viewer does |

`steps` is a struct of frame indices (column vectors) into `trace`:

| Field | Event |
|---|---|
| `rising` | Last frame at or below `threshold` before the trace rises above it |
| `falling` | First frame at or below `threshold` after the trace was above it |
| `onset` | Last frame at or below `nearZero` within `minInterval` frames before a rising crossing |
| `offset` | First frame at or below `nearZero` within `minInterval` frames after a falling crossing |
| `peak` | Local maxima at or above `threshold`, with a prominence of at least one SD of the trace |
| `valley` | Local minima at or below `threshold`, same prominence |
| `masked` | First frame of each masked period |

Masked frames are excluded: no event lies in them, and no search crosses them.
Convert indices to times with your frame times, e.g. `t_video(steps.peak)`.

## GAIT.sta

```matlab
result = GAIT.sta(emg, emg_t, event_time)
result = GAIT.sta(emg, emg_t, event_time, Name, Value, ...)
```

Averages one EMG channel around a set of event times and estimates the average
expected by chance. See [Step-triggered average](sta.md) for the controls and
how to read the result.

| Input | Description |
|---|---|
| `emg` | One EMG channel (vector). `NaN` samples are left out of the average |
| `emg_t` | Time of each sample (s). Must be regularly sampled, without gaps |
| `event_time` | Event times (s), on the same clock as `emg_t`. Events outside the recording are dropped with a warning |

| Name | Default | Description |
|---|---|---|
| `'max_lag'` | 0.5 | The average covers −max_lag to +max_lag seconds |
| `'method'` | `'dither'` | Control: `'dither'`, `'random_time'`, `'isi_shuffle'`, `'global'` or `'none'` |
| `'nRep'` | 100 | Number of surrogate event sets (`dither`, `random_time`, `isi_shuffle`) |
| `'offset'` | 1 | `dither` shifts each event by a random amount in [−offset, offset) s |
| `'zscore'` | `false` | Stored in the result; `GAIT.plot_sta` then plots in control SD units |
| `'nStd'` | 3 | Width of the control band in SD |
| `'plot'` | `false` | `true` plots in a new figure; an axes or figure handle plots there |

The controls:

| Method | Surrogate events |
|---|---|
| `dither` | Each real event shifted at random by up to ±`offset` |
| `random_time` | The same number of events at uniformly random times |
| `isi_shuffle` | The real inter-event intervals in random order |
| `global` | No surrogates: mean of the whole trace, SD = trace SD / √(events) |
| `none` | No control |

If a repeated control is estimated to take longer than 5 s, a dialog offers to
continue, switch to `global`, or skip the control.

`result` fields:

| Field | Description |
|---|---|
| `t` | Lag of each sample (s), from −max_lag to max_lag |
| `y` | The STA |
| `random_mean`, `random_std` | Mean and SD of the control at each lag |
| `method` | The control actually computed (it may differ after the dialog) |
| `eventNum` | Number of events used |
| `sampleCount` | Number of samples averaged at each lag |
| `sample_rate`, `max_lag`, `nRep`, `offset`, `zscore`, `nStd`, `random_t` | Settings used |

```matlab
r = GAIT.sta(env, t_emg, step_times, 'max_lag', 0.3, 'method', 'isi_shuffle', 'nRep', 500);
above = r.y > r.random_mean + r.nStd * r.random_std;   % lags above the band
```

## GAIT.plot_sta

```matlab
ax = GAIT.plot_sta(result)
ax = GAIT.plot_sta(result, target)
```

Plots a result of `GAIT.sta`: the STA (black line), the control mean (dashed)
with a band of ±`nStd` SD (shaded), a dotted line at lag 0, and the times of
the largest positive and negative deviations from the control mean. `target`
is an axes or figure handle; without it a new figure is opened. The axes are
cleared first. Returns the axes.

With `result.zscore` set (and a control), the plot is in control SD units:
(STA − control mean) / control SD, so the control mean is 0 and the band is
±`nStd`.

```matlab
figure; tiledlayout(1, 2);
GAIT.plot_sta(rTA, nexttile); title('TA');
rGS.zscore = true;
GAIT.plot_sta(rGS, nexttile); title('GS (z-score)');
```
