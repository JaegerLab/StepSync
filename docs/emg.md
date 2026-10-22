# EMG viewer

The EMG viewer reads multichannel recordings and finds the camera trigger.
Its preprocessing step prepares the signals for the step-triggered average.

<!-- SCREENSHOT: docs/images/emg-viewer.png. EMG viewer with a processed channel, the cursor line and step markers. -->

## Opening a recording

`File > Open` (Ctrl+O) asks for a **folder**. StepSync detects the format
from the folder contents.

### Intan (`.rhd`, `.rhs`)

- Every `.rhd`/`.rhs` file in the folder is read and joined in file-name
  order. Intan's software splits long recordings into consecutive files, and
  they are put back together this way.
- All files must have the same sample rate and channels. A warning appears if
  there is a gap between consecutive files.
- The amplifier channels are used as EMG, named by their custom channel names
  from the Intan software.
- Intan's software notch filter (50/60 Hz) is applied if it was enabled in
  the recording.

### Open Ephys

Select the session folder that contains the `Record Node` folder. Reading
needs [open-ephys-matlab-tools](https://github.com/open-ephys/open-ephys-matlab-tools)
on the path; StepSync shows a message if it is missing.

- If there are several record nodes, recordings or streams, you are asked to
  choose one.
- Channels named `CH…` are used as EMG and scaled to µV from the per-channel
  bit-volts value. `ADC…` channels are read but not displayed.

### Camera trigger

After reading, StepSync looks for the camera TTL line. If there is more than
one, it lists them with their pulse counts and frequencies (see
[Timing and synchronization](synchronization.md)). The info line then shows,
for example, `Rate: 20000 Hz, Length: 600.00 s` and
`Trigger#: 59990, Freq: 100 Hz`. If no trigger was found, it says
`Camera trigger not found.`

## Controls

| Control | Action |
|---|---|
| Info | Sample rate and length of the selected data type, and the trigger count and frequency |
| Push Frame Rate | Use the measured TTL frequency as the shared frame rate |
| time | Cursor time; type a value to jump |
| Pre-Process | Open the preprocessing window |
| Data type | `Raw`, `Processed 1`, `Processed 2`, … |
| ✕ | Delete the selected data type (asks first) |
| Load Channel Map | Label channels from a CSV file |
| Channel list | The channel to display (and to use for the STA) |
| Sort by | Order the channel list by a column of the channel map |

Click the plot to move the cursor. Raw data is drawn in blue, processed data
in green and the preprocessing preview in yellow. Steps from the Gait viewer
appear as magenta circles on the time axis.

## Channel map

A channel map is a CSV file with one row per channel, in recording order. Any
columns can be used. For example:

```csv
Channel,Muscle,Note
0,Rdelt,
1,Rdelt,
2,Rtri,
```

For differential (bipolar) recordings, the file can have two rows per
channel. The first row of each pair is used. Each channel is then listed as
its name followed by the values in its row, and **Sort by** orders the list by
any column, for example by muscle.

## Preprocessing

**Pre-Process** opens the preprocessing window. It processes the data type
currently selected in the viewer, so steps can be chained (for example, a
second down-sampling of *Processed 1*).

| Setting | Default | Description |
|---|---|---|
| High Pass | on, 500 Hz | 4th-order IIR (Butterworth) high-pass at the given half-power frequency |
| FiltFilt | off | Filter forwards and backwards (zero phase) instead of a causal filter |
| Rectify | on | Absolute value |
| Down Sample | on, 200 Hz | Smooth, then keep every *n*-th sample |

When down-sampling, the factor is *n* = round(*fs* / target rate). Before
decimation the signal is smoothed with a moving average of 2.5 *n* samples,
which acts as an envelope and anti-aliasing filter. The achieved rate is
*fs* / *n*, so it can differ slightly from the value entered. Samples before
time 0 are removed.

- **Preview** processes the selected channel only and draws it in yellow.
- **Apply & Close** processes all channels and adds a new data type
  `Processed N`. Earlier results are kept.
- **Cancel** discards the preview.

The settings and source of each processed type are stored with it (see
[Sessions and files](files.md)). A high-pass frequency above the Nyquist
frequency, or a target rate above the source rate, is rejected.

## Deleting data

**✕** deletes the selected data type. Deleting `Raw` frees memory once
processing is done. Raw data then comes back only by opening the recording
again. The remaining processed types are renumbered. The camera trigger and
channel names are kept, so video timing is unaffected. The button is disabled
while the preprocessing window is open.

## Saving and reopening

`File > Save` writes chosen data types to a `.mat` file, for the full length
or the current zoom window. `File > Open .mat` reads it back. You can leave
out the raw data when opening to save memory. See
[Sessions and files](files.md#emg-files).
