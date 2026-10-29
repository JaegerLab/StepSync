# Timing and synchronization

All StepSync windows share one clock, in seconds. When ephys data is loaded, this is
the ephys recording's clock: time 0 is the start of the recording. Video frames
and pose frames are placed on this clock. Gait events and the STA therefore
line up with the ephys samples recorded at the same moment.

## Frame times from camera TTL pulses

The recommended setup records the camera's exposure trigger on a digital
input of the ephys system. Each TTL rising edge marks one video frame.

When the ephys recording is opened, its digital inputs are listed in the trigger menu of
the Ephys viewer:

- **Intan:** the board digital inputs, e.g. `DIN-00`.
- **Open Ephys:** the TTL event lines of the selected stream, e.g. `TTL-01`.

Each item shows the pulse count, the median pulse width and the rate
(1 / median interval between pulses), for example
`DIN-00: 30900 TTL, 10 ms, 100 Hz` or `DIN-01: 1 TTL, 900 s, - Hz`, so the
camera line is easy to recognise. The menu reads `Select trigger channel`
until you choose one, `No digital channel` if the recording has none, and
`No data` before a recording is opened. Choosing `Select trigger channel`
again removes the trigger.

Frame *k* is then placed at the time of the *k*-th TTL pulse. This removes
drift between the camera and the acquisition system and needs no assumption
about the frame rate.

- The number of frames and the number of TTL pulses may differ by at most
  one. Cameras often record one extra frame or miss the last pulse. A final
  frame with no pulse gets no time and is excluded from analysis.
- A channel with fewer than two pulses, or with a pulse count that does not
  match the open video, pose or gait data, is refused with a message and the
  previous choice is kept. Check that the right line was chosen and that the
  video and pose files cover the same recording.
- The TTL times stay in use even if you later delete all ephys data types.

<!-- SCREENSHOT: docs/images/ttl-menu.png. The ephys trigger menu showing pulse counts, widths and rates. -->

## Frame rate

Without a trigger, frame *k* is placed at *k* / frame rate seconds, so frame
1 is at 1/frame rate, not 0. The frame rate is taken from the first available
of:

1. a rate typed into the frame rate box of the Video, Pose or Gait viewer;
2. the TTL frequency of the chosen trigger channel;
3. the frame rate stored in the video file;
4. 1 Hz. In this case the Pose viewer labels its axis "Frame" rather than
   "Time (s)".

The frame rate box shows `Frame rate: … Hz` in every viewer and updates
whenever a module is opened. An automatic rate (2–4) is shown in italics; the
tooltip says where it comes from. Clear the box or type 0 to return to the
automatic rate.

A typed-in rate also replaces the trigger times: frames are then placed at
*k* / frame rate even when a trigger is chosen. Use it when the triggers are
wrong. Choosing a trigger channel clears a typed-in rate. The frame rate is
also used for conversions such as speed (cm/s) and minimum step intervals.

## Moving between time and frames

When the cursor is at time *t*, viewers show the frame whose time is nearest
to *t*. Times before the first frame or after the last frame snap to the first
or last frame. Pose markers are hidden on frames beyond the end of the pose
file.

## Shared cursor and zoom

- Clicking a plot, typing a time, typing a frame number, or moving the video
  slider moves the shared cursor in every window.
- Zooming in or out (or panning with the plot tools) in the Ephys, Pose or Gait
  viewer changes the shared zoom window, and the other viewers follow.
- When the cursor reaches the edge of the zoom window, the window re-centres
  on the cursor, keeping its width.
- **Zoom window** saves (Ephys, Pose, Gait and Video `File > Save`) use the
  current zoom window as the time range. See [Sessions and files](files.md).
