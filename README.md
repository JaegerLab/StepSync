# StepSync

StepSync is a MATLAB application for aligning electromyography (EMG), video
and markerless pose tracking recorded during locomotion. It detects steps from
paw trajectories and computes step-triggered averages (STA) of muscle activity.

<!-- SCREENSHOT: docs/images/overview.png. All four viewers open side by side, with step markers visible in each. -->

## Features

- **One shared timeline.** Video, EMG, pose and gait windows follow the same
  cursor and zoom. Video frames are placed on the EMG clock using the camera
  TTL pulses recorded with the EMG.
- **EMG.** Reads Intan (`.rhd`/`.rhs`) and Open Ephys recordings. Preprocessing
  (high-pass filter, rectification, smoothing, down-sampling) can be chained,
  and channels can be labelled with a channel map.
- **Pose.** Reads DeepLabCut CSV, HDF5 and MAT files, and SLEAP exports in
  DeepLabCut CSV format. Tracking errors are corrected semi-automatically by
  segmenting each trajectory at jumps and interpolating through trusted
  segments. You can review and edit the result.
- **Gait.** Detects steps from paw x, y or speed (threshold crossings,
  movement onset and offset, peaks, valleys). Time-based and speed-based masks
  exclude unwanted periods.
- **Step-triggered average.** Averages EMG around step events against a chosen
  null distribution (dithered, shuffled or random events), with a ±3 SD band.
- **Sessions and exports.** Saves and restores whole sessions. Writes corrected
  pose files, EMG and gait `.mat` files, and videos with markers drawn in.

## Requirements

- MATLAB R2023a (the version StepSync was developed and tested with).
- Signal Processing Toolbox.
- For Open Ephys recordings only: [open-ephys-matlab-tools](https://github.com/open-ephys/open-ephys-matlab-tools)
  on the MATLAB path.

The Statistics and Machine Learning Toolbox is optional. It is only used by an
alternative jump-threshold method that the GUI does not call.

## Quick start

```matlab
% from the folder that contains StepSync.m
addpath(pwd)
StepSync('D:\my_data')   % the folder where file dialogs open first
```

The launcher opens with four buttons: **Video**, **EMG**, **DLC** and
**Gait**. A typical analysis:

1. **EMG:** `File > Open` a recording folder, and pick the camera TTL channel
   if asked.
2. **Video** (optional): `File > Open` the behaviour video.
3. **DLC:** `File > Open` the pose file, and correct tracking errors with **DLC Fix**.
4. **Gait:** `File > Import DLC`, choose the paws, set the threshold and mask,
   then open **Step Triggered Avg**.
5. `File > Save session` to keep everything.

The [Getting started](docs/getting-started.md) guide walks through this in
detail.

## Documentation

| Guide | Contents |
|---|---|
| [Getting started](docs/getting-started.md) | Installation, the launcher, menus, a first analysis |
| [Timing and synchronization](docs/synchronization.md) | How video frames are placed on the EMG clock |
| [Video viewer](docs/video.md) | Playback, pose markers, exporting marked videos |
| [EMG viewer](docs/emg.md) | Reading recordings, camera TTL, channel maps, preprocessing |
| [Pose viewer and correction](docs/pose.md) | Pose formats, frame alignment, the correction algorithm |
| [Gait analysis](docs/gait.md) | Step detection, event definitions, masks |
| [Step-triggered average](docs/sta.md) | STA computation and null controls |
| [Sessions and files](docs/files.md) | Session files, saved data formats, workspace export |

Tests are described in [tests/README.md](tests/README.md).

## Citation

A methods paper describing StepSync is in preparation. Until it is published,
please cite this repository:

> *Citation to be added.*

## License

StepSync is released under the [MIT License](LICENSE).

Bundled third-party code keeps its own terms:

- `+shared/fastsmooth.m` © 2012 Thomas C. O'Haver, MIT-style license (in the
  file header), modified to smooth matrices column-wise.
- `+EMG/read_Intan_RHD2000.m` and `+EMG/read_Intan_RHS2000.m` are adapted from
  the file readers published by Intan Technologies.
