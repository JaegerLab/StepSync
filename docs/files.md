# Sessions and files

StepSync saves two kinds of files:

- **Session files** hold everything needed to resume work.
- **Module files** hold one module's data, for sharing or for later analysis
  outside StepSync.

All `.mat` files are written in MATLAB v7.3 format and carry a `fileFormat`
and a `formatVersion` variable, so StepSync can recognise them.

## Sessions

`File > Save session` asks which open modules to include and writes one
`.mat` file. It stores:

- the frame rate, cursor time and zoom window;
- each module's window position, control settings and data.

`File > Load session` closes all module windows (after asking), then reopens
the saved modules exactly as they were.

| Variable | Contents |
|---|---|
| `fileFormat` | `'StepSync session'` |
| `formatVersion` | `3` |
| `frameRate`, `currentTime`, `currentZoom` | Shared timing state |
| `figures` | Window position of each saved module |
| `video`, `emg`, `dlc`, `gait` | Module data, with control settings in `.parameters` |

## Module files

Each module's `File > Save` asks whether to save the **full length** or only
the current **zoom window**. The default file name ends in `_StepSync` (or
`_gait`), and the file a module was opened from is never overwritten.

### EMG files

`File > Save` in the EMG viewer asks which data types to save, then writes:

| Variable | Contents |
|---|---|
| `fileFormat`, `formatVersion` | `'StepSync EMG'`, `1` |
| `emg` | Channel names and units, camera trigger, channel map, source, `time_range` (empty for full length) |
| `raw` | `data` (samples × channels), `t` (s), `sample_rate` (Hz) |
| `processed1`, `processed2`, … | As `raw`, plus `parameters`: `FilterType`, `HighPassFreq`, `LowPassFreq`, `FiltFilt`, `Rectify`, `DownSampleRate`, `Source` |

Times are on the original recording clock, also in a zoom-window save.
EMG `File > Open File` with a `.mat` file lists the stored types with their sizes, so you can load
only what you need.

### Pose files

`File > Save` in the DLC viewer writes a DeepLabCut-format CSV:

- three header rows: `scorer`, `bodyparts`, `coords` (`x`, `y`,
  `likelihood`);
- a first column with the zero-based frame number in the original video;
- all body parts, including corrected ones.

Missing values are written as `NaN`. Corrected body parts carry the
likelihood codes described in [Pose viewer and correction](pose.md#how-it-works).

### Gait files

`File > Save` in the Gait viewer writes:

| Variable | Contents |
|---|---|
| `fileFormat`, `formatVersion` | `'StepSync gait'`, `1` |
| `gait.paw` | `name`, `raw_x`, `raw_y` (pixels) and thresholds of each paw |
| `gait.mask`, `gait.maskParam` | The mask and the mask editor's settings |
| `gait.selection` | Selected paw, trace and event type |
| `gait.resolution`, `gait.minInterval`, `gait.frameRate` | Settings |
| `gait.sta` | STA history |
| `gait.filename`, `gait.source` | The pose file the paws came from |
| `gait.time_range` | Empty for full length |

Step events, speeds and centimetre traces are not stored. They are
recalculated when the file is opened. In a zoom-window save, frames outside
the window are set to `NaN` and masked, and the frame count is unchanged.

### Videos

`File > Save` in the Video viewer exports an MPEG-4 video with markers drawn
in. See [Video viewer](video.md#exporting-a-marked-video).

## Export to Workspace

`File > Export to Workspace` assigns the session object to a variable in the
MATLAB base workspace (default name `data`; existing variables are not
overwritten). It is the live object, so it reflects later changes in
StepSync. Main fields:

| Field | Contents |
|---|---|
| `data.frameRate`, `data.currentTime`, `data.currentZoom` | Shared state |
| `data.getFrameTimes(n)` | Times (s) of video frames 1…n |
| `data.emg.raw`, `data.emg.processed(k)` | `data`, `t`, `sample_rate` (and `parameters`) |
| `data.emg.digital` | Digital channels: `name`, `rise`, `fall` edge times |
| `data.emg.trigger` | Chosen camera TTL: `channel`, `time`, `freq`, `number` |
| `data.dlc.table` | Pose table: `<part>_x`, `<part>_y`, `<part>_likelihood` |
| `data.dlc.t` | Time of each pose frame |
| `data.gait.t` | Time of each gait frame |
| `data.gait.mask` | Logical mask (true = analysed) |
| `data.gait.paw(i)` | `name`, `x`, `y` (cm), `speed` (cm/s), and events `rising`, `falling`, `onset`, `offset`, `peak`, `valley`, `masked` (frame indices) |
| `data.gait.sta(j)` | STA runs: `t`, `y`, `random_mean`, `random_std`, `sampleCount`, parameters and selections |

Events are only up to date for the paw and trace selected in the Gait viewer.
