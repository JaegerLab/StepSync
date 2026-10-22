# Getting started

## Installation

1. Install MATLAB R2023a with the Signal Processing Toolbox.
2. Download or clone this repository:

   ```bash
   git clone https://github.com/JaegerLab/StepSync.git
   ```

3. To read Open Ephys recordings, also install
   [open-ephys-matlab-tools](https://github.com/open-ephys/open-ephys-matlab-tools)
   and add it to the MATLAB path. Intan recordings need nothing extra.

StepSync is organised as MATLAB packages (`+EMG`, `+DLC`, `+GAIT`, `+VIDEO`,
`+shared`). Add only the repository root to the path, not the package folders:

```matlab
addpath('C:\path\to\StepSync')
```

## Starting StepSync

```matlab
StepSync('D:\my_data')
```

The argument is the folder where file dialogs first open. After that,
StepSync remembers the folder of the last file you opened or saved. Calling
`StepSync` with no argument opens the dialogs in a lab-specific default
folder, so it is best to pass your own.

<!-- SCREENSHOT: docs/images/launcher.png. The launcher window with its four buttons. -->

The launcher has one button per module: **Video**, **EMG**, **DLC** (pose)
and **Gait**. Opening a module closes the launcher. If StepSync windows are
already open, running `StepSync` again brings them to the front.

## Windows and menus

Each module opens in its own window. The Video, EMG, DLC and Gait windows
share one cursor time and one zoom window. Clicking a trace in any viewer
moves the cursor in all of them, and zooming in one zooms the others.

Every module window has the same menu bar.

**File**

| Item | Shortcut | Action |
|---|---|---|
| Open | Ctrl+O | Open a file for this module |
| Save | Ctrl+S | Save this module's data (see [Sessions and files](files.md)) |
| *(module-specific items)* | | EMG: **Open .mat**. Gait: **Import DLC** |
| Load session | | Replace everything with a saved session |
| Save session | | Save the open modules to one session file |
| Export to Workspace | | Put the session data in the MATLAB base workspace |
| Close | Ctrl+W | Close this window (asks first) |
| Exit all | | Close every StepSync window (asks first) |

**Window**

| Item | Shortcut |
|---|---|
| Video | Ctrl+I |
| EMG | Ctrl+E |
| DLC | Ctrl+D |
| Gait | Ctrl+G |
| Open All | Ctrl+A |
| Bring All to Top | Ctrl+T |

A check mark shows which modules are open. Open tool windows (EMG
Pre-Process, DLC auto fix, Edit Mask, Step-Triggered Average) are listed
indented under their module, and choosing one brings it to the front. On
macOS the shortcuts use Cmd instead of Ctrl.

When the last module window closes, the session ends and its data is cleared.
Save the session first if you need it.

The EMG, DLC and Gait viewers all have these buttons below their plot:

| Button | Action |
|---|---|
| 🔍︎+ / 🔍︎- | Halve / double the zoom window around the cursor |
| ⭯ Refresh | Show the full recording and reset the vertical axis |
| [➜ Pop out | Copy the plot into an ordinary MATLAB figure, for export or editing |

## A first analysis

The order below is the usual one. Opening the EMG first means video and pose
frames are timed by the camera TTL pulses from the start.

1. **EMG.** In the EMG viewer, choose `File > Open` and select the folder
   that holds the recording. If the recording has more than one digital input,
   choose the line that carries the camera trigger. The info line then shows
   the number of TTL pulses and their frequency. See [EMG viewer](emg.md).
2. **Preprocess EMG** (optional). Click **Pre-Process**, check the settings,
   **Preview** one channel, then **Apply & Close**. The result appears as
   *Processed 1* in the data-type list.
3. **Video** (optional). In the Video viewer, choose `File > Open`. The video
   is shown on the EMG time base. See [Video viewer](video.md).
4. **Pose.** In the DLC viewer, choose `File > Open` and pick the pose file.
   Use **DLC Fix** to correct tracking errors and **Save As** the corrected
   body part. See [Pose viewer and correction](pose.md).
5. **Gait.** In the Gait viewer, choose `File > Import DLC` and select the
   paws. Set **Resolution** (pixels per cm), the trace (X, Y or Speed) and a
   threshold. Use **Edit Mask** to exclude periods you don't want to analyse.
   Step events appear as magenta circles in every viewer. See
   [Gait analysis](gait.md).
6. **STA.** Pick the EMG channel and data type in the EMG viewer, and the paw
   and event type in the Gait viewer. Then click **Step Triggered Avg** and
   **Plot**. See [Step-triggered average](sta.md).
7. **Save.** `File > Save session` stores the data, settings and window
   positions of the modules you choose.

## Working with results in MATLAB

`File > Export to Workspace` puts the session in the base workspace under a
name you choose (default `data`). The variable is the live session object, not
a copy, so it keeps changing while StepSync runs:

```matlab
data.gait.paw(1).onset        % onset frame indices of the first paw
data.gait.t(data.gait.paw(1).onset)   % ...and their times in seconds
data.gait.sta(end)            % the most recent STA result
```

[Sessions and files](files.md) lists the fields.
