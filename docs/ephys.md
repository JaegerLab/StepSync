# Ephys viewer

The Ephys viewer reads multichannel recordings and finds the camera trigger.
Its preprocessing step prepares the signals for the step-triggered average.

<!-- SCREENSHOT: docs/images/ephys-viewer.png. Ephys viewer with a processed channel, the cursor line and step markers. -->

## Opening a recording

- `File > Open File` (Ctrl+O) selects one or more `.rhd`/`.rhs` files, or a
  single `.mat` file written by Save (see [Saving and reopening](#saving-and-reopening)).
- `File > Open folder` asks for a **folder**. StepSync detects the format
  from the folder contents.

### Intan (`.rhd`, `.rhs`)

- The selected files, or every `.rhd`/`.rhs` file in the folder, are read and
  joined in file-name order. Intan's software splits long recordings into consecutive files, and
  they are put back together this way.
- All files must have the same sample rate and channels. A warning appears if
  there is a gap between consecutive files.
- The amplifier channels are the analog channels, named by their custom channel names
  from the Intan software.
- Intan's software notch filter (50/60 Hz) is applied if it was enabled in
  the recording.

### Open Ephys

Select the session folder that contains the `Record Node` folder. Reading
needs [open-ephys-matlab-tools](https://github.com/open-ephys/open-ephys-matlab-tools)
on the path; StepSync shows a message if it is missing.

- If there are several record nodes, recordings or streams, you are asked to
  choose one.
- Channels named `CH…` are the analog channels and are scaled to µV from the per-channel
  bit-volts value. `ADC…` channels are read but not displayed.

### Camera trigger

After reading, the trigger menu lists the digital channels with their pulse
counts, widths and rates, e.g. `DIN-00: 30900 TTL, 10 ms, 100 Hz`. Choose the
camera line to synchronize the frames (see
[Timing and synchronization](synchronization.md)). The info line then shows,
for example, `Rate: 20000 Hz, Length: 600.00 s` and
`Trigger#: 59990, Freq: 100 Hz`. Until a channel is chosen, it says
`No camera trigger selected.`

## Controls

| Control | Action |
|---|---|
| Info | Sample rate and length of the selected data type, and the trigger count and frequency |
| Trigger menu | The digital channel that carries the camera trigger; `Select trigger channel` for none |
| time | Cursor time; type a value to jump |
| Pre-Process | Open the preprocessing window |
| Data type | `Raw`, `Processed 1`, `Processed 2`, … |
| ✕ | Delete the selected data type (asks first) |
| Load Channel Map | Label channels from a CSV file |
| Channel list | The channel to display (and to use for the STA) |
| Sort by | Order the channel list by a column of the channel map |

Click the plot to move the cursor. Raw data is drawn in blue, processed data
in green and the preprocessing preview in yellow. Steps from the Gait viewer
appear as magenta circles on the ephys trace.

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
second down-sampling of *Processed 1*). The window shows the settings of the
selected type: the ones a processed type was made with, or the defaults
below for `Raw`. Selecting another type also discards the preview.

| Setting | Default | Description |
|---|---|---|
| Filter | on, High pass | 4th-order IIR (Butterworth): High pass, Low pass, Band pass or Band stop |
| High | 500 Hz | High-pass half-power frequency; a band edge for Band pass and Band stop |
| Low | 5000 Hz | Low-pass half-power frequency; a band edge for Band pass and Band stop |
| Filtfilt | off | Filter forwards and backwards (zero phase) instead of a causal filter |
| Rectify | on | Absolute value |
| Down Sample | on, 200 Hz | Smooth, then resample at exactly the given sample rate |

Only the settings that apply are enabled: Filtfilt and the filter type need
Filter, High pass uses only High, Low pass only Low, and the band filters both.

When down-sampling, the signal is first smoothed with a moving average of
2.5 *fs* / rate samples, which acts as an envelope and anti-aliasing filter.
It is then linearly interpolated at multiples of 1 / rate from time 0, so
the new rate is exactly the value entered. Samples before
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
or the current zoom window. `File > Open File` reads it back. You can leave
out the raw data when opening to save memory. See
[Sessions and files](files.md#ephys-files).
