# Timing and synchronization

All StepSync windows share one clock, in seconds. When EMG is loaded, this is
the EMG recording's clock: time 0 is the start of the recording. Video frames
and pose frames are placed on this clock. Gait events and the STA therefore
line up with the EMG samples recorded at the same moment.

## Frame times from camera TTL pulses

The recommended setup records the camera's exposure trigger on a digital
input of the EMG system. Each TTL rising edge marks one video frame.

When the EMG is opened, StepSync finds the rising edges on the chosen digital
line:

- **Intan:** the board digital inputs. If there is more than one, a dialog
  lists each channel as `Ch k: N TTL, F Hz`, so the camera line is easy to
  recognise by its pulse count and rate.
- **Open Ephys:** the TTL event lines of the selected stream, listed in the
  same way.

With one line, it is used automatically. If you cancel the dialog, no
trigger is used.

Frame *k* is then placed at the time of the *k*-th TTL pulse. This removes
drift between the camera and the acquisition system and needs no assumption
about the frame rate.

- The number of frames and the number of TTL pulses may differ by at most
  one. Cameras often record one extra frame or miss the last pulse. A final
  frame with no pulse gets no time and is excluded from analysis.
- A larger mismatch is reported as an error, because the frames could no
  longer be matched to pulses reliably. Check that the right TTL line was
  chosen and that the video and pose files cover the same recording.
- The TTL times stay in use even if you later delete all EMG data types.

<!-- SCREENSHOT: docs/images/ttl-dialog.png. The camera TTL channel dialog showing pulse counts and frequencies. -->

## Without TTL pulses

If no camera trigger is available, frame *k* is placed at *k* / frame rate
seconds, so frame 1 is at 1/frame rate, not 0. The frame rate is taken from
the first available of:

1. a rate typed into the frame rate box of the Video, DLC or Gait viewer;
2. the TTL frequency (1 / median interval between pulses);
3. the frame rate stored in the video file;
4. 1 Hz. In this case the DLC viewer labels its axis "Frame" rather than
   "Time (s)".

**Push Frame Rate** in the EMG viewer copies the measured TTL frequency into
the shared frame rate. The frame rate is used for conversions such as speed
(cm/s) and minimum step intervals. When TTL times exist, frame times always
come from the TTLs.

## Moving between time and frames

When the cursor is at time *t*, viewers show the frame whose time is nearest
to *t*. Times before the first frame or after the last frame snap to the first
or last frame. Pose markers are hidden on frames beyond the end of the pose
file.

## Shared cursor and zoom

- Clicking a plot, typing a time, typing a frame number, or moving the video
  slider moves the shared cursor in every window.
- Zooming in or out (or panning with the plot tools) in the EMG, DLC or Gait
  viewer changes the shared zoom window, and the other viewers follow.
- When the cursor reaches the edge of the zoom window, the window re-centres
  on the cursor, keeping its width.
- **Zoom window** saves (EMG, DLC, Gait and Video `File > Save`) use the
  current zoom window as the time range. See [Sessions and files](files.md).
