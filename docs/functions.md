# Command-line functions

The viewers are built on a few functions that also work on their own, from the
command line or in your own scripts. They take plain arrays, need no open
window and no session, and return plain MATLAB data.

| Function | Purpose |
|---|---|
| [`ephys.ephys_prep`](#ephysephys_prep) | Filter, rectify, smooth and down-sample ephys data |
| [`pose.pose_fix`](#posepose_fix) | Correct jumps (mislabels) in a pose trajectory |
| [`gait.detect_steps`](#gaitdetect_steps) | Find step events in a paw trace |
| [`gait.sta`](#gaitsta) | Step-triggered average with a chance-level control |
| [`gait.plot_sta`](#gaitplot_sta) | Plot a result of `gait.sta` |

Add the StepSync folder (the one that contains `StepSync.m`) to the path; the
functions are in the packages `+ephys`, `+pose` and `+gait`, so they are called
with the package prefix. `help pose.pose_fix` and so on print the full help.

## A complete example

```matlab
addpath('C:\path\to\StepSync')

% Ephys: read an EMG recording, rectify and down-sample channel 3 to 1 kHz
rec = ephys.ephys_read('D:\data\mouse1\emg');
opt = struct('HighPassFreq', 50, 'Rectify', true, 'DownSampleRate', 1000);
[env, t_emg] = ephys.ephys_prep(rec.analogData(:,3), rec.t, opt, rec.sampleRate);

% Pose: read DeepLabCut output and fix the right hind paw
T = pose.read_pose('D:\data\mouse1\video1DLC.csv');
[x, y] = pose.pose_fix(T.RH_x, T.RH_y);

% Gait: speed in cm/s, then movement onsets
fps = 200; px_per_cm = 20;                       % your camera
speed = gait.smooth_speed(x, y, 3) * fps / px_per_cm;
t_video = (0:numel(speed)-1)' / fps;             % or frame times from the TTL
steps = gait.detect_steps(speed, true(size(speed)), 10, round(0.1*fps), 2);

% STA of the EMG envelope around the onsets
result = gait.sta(env, t_emg, t_video(steps.onset), 'maxLag', 0.3);
gait.plot_sta(result);
```

The times passed to `gait.sta` must be on the ephys clock. In the GUI, video
frames are placed on that clock from the camera TTL pulses (see
[Timing and synchronization](synchronization.md)); in a script you supply the
frame times yourself.

## ephys.ephys_prep

```matlab
[newData, newT] = ephys.ephys_prep(data, t, options)
[newData, newT] = ephys.ephys_prep(data, t, options, fs)
```

Preprocesses ephys data in a fixed order: filter, rectify, smooth and
down-sample. Every step is optional and is switched on by a field of `options`.
This is what **Pre-Process** in the [Ephys viewer](ephys.md) runs.

| Input | Description |
|---|---|
| `data` | Samples × channels. Each column is processed independently |
| `t` | Time of each sample (s), a vector with one value per row of `data` |
| `options` | Struct; leave a field out to skip that step (see below) |
| `fs` | Sample rate (Hz). Default: `1/mean(diff(t))` |

| `options` field | Effect |
|---|---|
| `FilterType` | `'highpass'`, `'lowpass'`, `'bandpass'` or `'bandstop'`: 4th-order IIR (Butterworth). Default: `'highpass'` or `'lowpass'` when only that frequency is given, `'bandpass'` when both are |
| `HighPassFreq` | High-pass cutoff (Hz); a band edge for band filters |
| `LowPassFreq` | Low-pass cutoff (Hz); a band edge for band filters. A band filter passes or stops the band between the two frequencies |
| `FiltFilt` | `true`: zero-phase filtering with `filtfilt`. `false` (default): causal `filter` |
| `Rectify` | `true`: absolute value. Default `false` |
| `DownSampleRate` | New sample rate (Hz). The data are smoothed with a moving window of 2.5 × `fs/DownSampleRate` samples, then linearly interpolated at `k/DownSampleRate` (*k* = 0, 1, 2, …), so the rate is exact |

| Output | Description |
|---|---|
| `newData` | Processed data |
| `newT` | Time of each output sample |

Samples at negative time (before the recording started) are dropped. A progress
bar is shown while the function runs.

```matlab
% envelope at ~500 Hz, zero-phase filter
opt = struct('HighPassFreq', 30, 'FiltFilt', true, 'Rectify', true, 'DownSampleRate', 500);
[env, t2] = ephys.ephys_prep(raw, t, opt, 30000);

% band pass 20-450 Hz, no envelope
opt = struct('FilterType', 'bandpass', 'HighPassFreq', 20, 'LowPassFreq', 450);
bp = ephys.ephys_prep(raw, t, opt, 30000);
```

## pose.pose_fix

```matlab
[xFix, yFix, mask, seg] = pose.pose_fix(x, y)
[xFix, yFix, mask, seg] = pose.pose_fix(x, y, jumpThresh, seedWidth)
[xFix, yFix, mask, seg] = pose.pose_fix(x, y, jumpThresh, seedWidth, maskOrSeg)
[...] = pose.pose_fix(..., visualize)
```

Corrects short tracking errors in one body part's trajectory. The trace is cut
into segments at jumps larger than `jumpThresh`. Segments at least
`seedWidth` frames long are trusted seeds, and the remaining segments are
accepted or rejected by comparing them with an interpolation through the
trusted frames. The rejected frames are then replaced by that interpolation.
The algorithm is described in [Pose viewer and correction](pose.md). This is
what **Pose Fix** runs.

| Input | Description |
|---|---|
| `x`, `y` | Coordinates of one body part, in pixels (vectors of equal length) |
| `jumpThresh` | Jump threshold (pixels). `[]` or omitted: estimated by `pose.auto_jump_threshold` |
| `seedWidth` | Seed width (frames). `[]` or omitted: estimated by `pose.auto_window_width` |
| `maskOrSeg` | Optional. A logical vector (one value per frame) marks frames you already know to be good (`true`) or bad (`false`): good runs become seeds, bad runs are rejected, and nothing is propagated. A segment structure (`seg` from an earlier call, possibly edited) re-runs the algorithm only around the edited segments |
| `visualize` | `true` to plot the result, with the same layers and styles as the correction overlay in the Pose viewer (`pose.fix_style`), plus the suggested fix at each conflict. Default `false` |

| Output | Description |
|---|---|
| `xFix`, `yFix` | Corrected trajectory: a pchip interpolation through the good frames. Before the first and after the last good frame the nearest good value is held |
| `mask` | Logical, `true` for frames in good segments |
| `seg` | Segment structure: start, stop, length and flag of each segment, the jumps, and conflicts with suggested fixes. See `help pose.pose_seg_build` |

Segment flags in `seg.flag`: 2 seed, 1 good, 0 undetermined, −1 bad,
−2 questionable, −3 rejected. `pose.seg_likelihood(seg)` turns them into a
per-frame likelihood, as used when the GUI saves a fixed body part.

```matlab
T = pose.read_pose('video1DLC.csv');            % columns <bodypart>_x/_y/_likelihood
[xf, yf, good, seg] = pose.pose_fix(T.nose_x, T.nose_y, 20, 60, [], true);

% use likelihood as prior knowledge instead of propagation
[xf, yf] = pose.pose_fix(T.nose_x, T.nose_y, 20, [], T.nose_likelihood > 0.9);

% mark segment 12 as good by hand, then update only around it
seg.flag(12) = 2; seg.isNew(12) = true;
[xf, yf, good, seg] = pose.pose_fix(T.nose_x, T.nose_y, [], [], seg);
```

When a segment structure is passed, `jumpThresh` and `seedWidth` default to
the values stored in it. To add or remove a jump in `seg`, use
`pose.pose_seg_toggle_jump`.

## gait.detect_steps

```matlab
steps = gait.detect_steps(trace, mask, threshold, minInterval)
steps = gait.detect_steps(trace, mask, threshold, minInterval, nearZero)
```

Finds step events in one paw trace (x, y or speed). The event definitions are
those of the [Gait viewer](gait.md#step-events).

| Input | Description |
|---|---|
| `trace` | Paw trace, one value per frame |
| `mask` | Logical, `false` for frames to exclude. Use `true(size(trace))` for no mask |
| `threshold` | Threshold in the units of `trace` |
| `minInterval` | Minimum distance between peaks and valleys, in **frames** (a positive integer) |
| `nearZero` | Speed treated as rest, for onset and offset. Default `NaN` (no onsets or offsets). `gait.auto_rest_threshold(speed, fps)` estimates it as the Gait viewer does |

`steps` is a struct of frame indices (column vectors) into `trace`:

| Field | Event |
|---|---|
| `rising` | Last frame at or below `threshold` before the trace rises above it |
| `falling` | First frame at or below `threshold` after the trace was above it |
| `onset` | Last frame at or below `nearZero` before a rising crossing, back to the previous falling crossing |
| `offset` | First frame at or below `nearZero` after a falling crossing, up to the next rising crossing |
| `peak` | Local maxima at or above `threshold`, with a prominence of at least one SD of the trace |
| `valley` | Local minima at or below `threshold`, same prominence |
| `masked` | First frame of each masked period |

Masked frames are excluded: no event lies in them, and no search crosses them.
Convert indices to times with your frame times, e.g. `t_video(steps.peak)`.

## gait.sta

```matlab
result = gait.sta(signal, signalT, eventTime)
result = gait.sta(signal, signalT, eventTime, Name, Value, ...)
```

Averages one ephys channel around a set of event times and estimates the average
expected by chance. See [Step-triggered average](sta.md) for the controls and
how to read the result.

| Input | Description |
|---|---|
| `signal` | One ephys channel (vector). `NaN` samples are left out of the average |
| `signalT` | Time of each sample (s). Must be regularly sampled, without gaps |
| `eventTime` | Event times (s), on the same clock as `signalT`. Events outside the recording are dropped with a warning |

| Name | Default | Description |
|---|---|---|
| `'maxLag'` | 0.5 | The average covers −maxLag to +maxLag seconds |
| `'method'` | `'dither'` | Control: `'dither'`, `'random_time'`, `'isi_shuffle'`, `'global'` or `'none'` |
| `'nRep'` | 100 | Number of surrogate event sets (`dither`, `random_time`, `isi_shuffle`) |
| `'offset'` | 1 | `dither` shifts each event by a random amount in [−offset, offset) s |
| `'zscore'` | `false` | Stored in the result; `gait.plot_sta` then plots in control SD units |
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
| `t` | Lag of each sample (s), from −maxLag to maxLag |
| `y` | The STA |
| `randomMean`, `randomStd` | Mean and SD of the control at each lag |
| `method` | The control actually computed (it may differ after the dialog) |
| `eventNum` | Number of events used |
| `sampleCount` | Number of samples averaged at each lag |
| `sampleRate`, `maxLag`, `nRep`, `offset`, `zscore`, `nStd`, `randomT` | Settings used |

```matlab
r = gait.sta(env, t_emg, step_times, 'maxLag', 0.3, 'method', 'isi_shuffle', 'nRep', 500);
above = r.y > r.randomMean + r.nStd * r.randomStd;   % lags above the band
```

## gait.plot_sta

```matlab
ax = gait.plot_sta(result)
ax = gait.plot_sta(result, target)
```

Plots a result of `gait.sta`: the STA (black line), the control mean (dashed)
with a band of ±`nStd` SD (shaded), a dotted line at lag 0, and the times of
the largest positive and negative deviations from the control mean. `target`
is an axes or figure handle; without it a new figure is opened. The axes are
cleared first. Returns the axes.

With `result.zscore` set (and a control), the plot is in control SD units:
(STA − control mean) / control SD, so the control mean is 0 and the band is
±`nStd`.

```matlab
figure; tiledlayout(1, 2);
gait.plot_sta(rTA, nexttile); title('TA');
rGS.zscore = true;
gait.plot_sta(rGS, nexttile); title('GS (z-score)');
```
