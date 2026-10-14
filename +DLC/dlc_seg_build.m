function seg = dlc_seg_build(x, y, jump_thresh, win_width, extra_breaks)
%DLC_SEG_BUILD  Split a DLC trajectory into segments at jumps.
%
%   seg = DLC.dlc_seg_build(x, y, jump_thresh)
%   seg = DLC.dlc_seg_build(x, y, jump_thresh, win_width)
%   seg = DLC.dlc_seg_build(x, y, jump_thresh, win_width, extra_breaks)
%
%   A jump is a frame-to-frame displacement > jump_thresh, or a NaN
%   displacement. Segment m runs from seg.start(m) to seg.stop(m); jump k
%   lies between segment k and k+1, i.e. after frame seg.stop(k).
%   If win_width is given, segments with len >= win_width are flagged as
%   seeds. extra_breaks (frame indices t) adds boundaries after frame t,
%   e.g. where a mask changes value.
%
%   Segment structure (shared by dlc_fix_predict and auto_window_width)
%   Per segment (M x 1):
%     start, stop, len   first frame, last frame, number of frames
%     flag               2  seed (>= win_width, or confirmed by the user)
%                        1  good, recovered by propagation
%                        0  not flagged yet
%                       -1  bad (jumped away from a good neighbour)
%                       -2  questionable (checked, did not match)
%                       -3  rejected by the user (locked bad)
%                        good frames: flag > 0
%     is_new             true = edited, recheck around it (see dlc_fix_predict)
%     round              propagation round in which the flag was set
%                        (0 for seeds/locked, NaN if never flagged)
%     err                distance to the interpolation when last checked
%   Per jump ((M-1) x 1):
%     conflict           both neighbouring segments are good
%     suggestion         '', 'merge', 'split' or 'review' (conflicts only)
%     suggest_at         frame t to pass to dlc_seg_toggle_jump (NaN if none)
%   Scalars:
%     n_frames, jump_thresh, win_width (NaN if unknown)

if nargin < 4 || isempty(win_width), win_width = NaN; end
if nargin < 5, extra_breaks = []; end

x = x(:); y = y(:);
N = numel(x);
d = hypot(diff(x), diff(y));
J = find(d > jump_thresh | ~isfinite(d));
J = unique([J; extra_breaks(:)]);
J = J(J >= 1 & J < N);

S = [1; J + 1];
E = [J; N];
M = numel(S);

seg = struct();
seg.start      = S;
seg.stop       = E;
seg.len        = E - S + 1;
seg.flag       = zeros(M, 1);
seg.is_new     = false(M, 1);
seg.round      = nan(M, 1);
seg.err        = nan(M, 1);
seg.conflict   = false(M - 1, 1);
seg.suggestion = repmat({''}, M - 1, 1);
seg.suggest_at = nan(M - 1, 1);
seg.n_frames    = N;
seg.jump_thresh = jump_thresh;
seg.win_width   = win_width;

if ~isnan(win_width)
    isSeed = seg.len >= win_width;
    seg.flag(isSeed)  = 2;
    seg.round(isSeed) = 0;
end
end
