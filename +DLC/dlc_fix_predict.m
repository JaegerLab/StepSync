function [x_fix, y_fix, mask, seg] = dlc_fix_predict(x, y, jump_thresh, win_width, mask_or_seg, visualize)
%DLC_FIX_PREDICT  Fix DLC mislabels by progressive interpolation from seeds.
%
%   [x_fix, y_fix, mask, seg] = DLC.dlc_fix_predict(x, y)
%   [x_fix, y_fix, mask, seg] = DLC.dlc_fix_predict(x, y, jump_thresh, win_width)
%   [x_fix, y_fix, mask, seg] = DLC.dlc_fix_predict(x, y, jump_thresh, win_width, mask_or_seg)
%   [...] = DLC.dlc_fix_predict(..., visualize)
%
%   The trace is cut into segments at jumps. Segments at least win_width
%   long are seeds. Propagation then repeats:
%     1. undecided segments next to a good one are bad (a jump separates
%        them from a known-good position);
%     2. undecided segments next to a bad/questionable one are candidates:
%        the label may have come back. Each candidate edge that faces a
%        flagged neighbour is compared with a pchip interpolation through
%        all good frames (median over CHECK_FRAMES frames). If every
%        checked edge is within jump_thresh the candidate is good,
%        otherwise questionable. Two neighbouring candidates cannot both
%        become good in the same round: the closer match wins.
%   until no new good segments appear. Afterwards, neighbouring good
%   segments (which a jump says cannot both be right) are marked as
%   conflicts with a suggested fix.
%
%   Inputs
%     x, y         coordinates of one body part (vectors, same length)
%     jump_thresh  jump threshold. [] -> seg.jump_thresh if a segment
%                  structure is given, else DLC.auto_jump_threshold.
%     win_width    seed width in frames. [] -> seg.win_width if given,
%                  else DLC.auto_window_width (only computed if needed).
%     mask_or_seg  optional:
%                  - logical (or 0/1) vector, one value per frame: segments
%                    are cut at jumps and where the mask changes; good runs
%                    become seeds, bad runs locked bad. No propagation.
%                  - segment structure (see DLC.dlc_seg_build):
%                    * segments with is_new = true were edited. A positive
%                      flag makes it a seed, a negative one locks it bad,
%                      flag 0 (new geometry after split/merge) re-judges it
%                      (seed if len >= win_width, else propagation). Only
%                      the stretch between the nearest original seeds on
%                      either side is rechecked.
%                    * any other flag-0 segments are propagated as usual.
%     visualize    true to plot the result (default false)
%
%   Outputs
%     x_fix, y_fix interpolated (pchip) through good frames; before the
%                  first / after the last good frame the nearest good value
%                  is held
%     mask         logical, true for frames in good segments (flag > 0)
%     seg          segment structure (flags, rounds, conflicts, suggestions)
%
%   Suggestions for conflicts (seg.suggestion, at jump k)
%     'split'  a hidden sub-threshold jump inside one side cancels the
%              detected jump, and the label stays put in between;
%              seg.suggest_at is the frame to split after
%     'merge'  the jump is close to the threshold and the motion carries on
%              in its direction, so it is probably real fast movement;
%              seg.suggest_at is the jump to remove
%     'review' neither; often a long stretch stuck on the wrong body part
%   Apply split/merge with DLC.dlc_seg_toggle_jump(seg, seg.suggest_at(k)).
%
%   See also DLC.dlc_seg_build, DLC.dlc_seg_toggle_jump, DLC.dlc_seg_mask,
%            DLC.auto_jump_threshold, DLC.auto_window_width.

% ---- tunable constants --------------------------------------------------
P.CHECK_FRAMES = 3;    % edge frames compared with the interpolation (median)
P.CANCEL_TOL   = 0.3;  % hidden jump: |jump + hidden step| < CANCEL_TOL*|jump|
P.HIDDEN_LAGS  = 3;    % a hidden jump may be spread over up to this many frames
P.MERGE_RATIO  = 1.5;  % 'merge' only for jumps below MERGE_RATIO*jump_thresh
P.MERGE_FRAMES = 5;    % frames of motion checked for continuing direction

SEED = 2; GOOD = 1; REJECT = -3;

% ---- inputs ---------------------------------------------------------------
x = x(:); y = y(:);
N = numel(x);
if numel(y) ~= N
    error('dlc_fix_predict:size', 'x and y must have the same length.');
end
if nargin < 3, jump_thresh = []; end
if nargin < 4, win_width = []; end
if nargin < 5, mask_or_seg = []; end
if nargin < 6 || isempty(visualize), visualize = false; end

if isempty(mask_or_seg)
    mode = 'full';
elseif isstruct(mask_or_seg)
    mode = 'seg';
elseif (islogical(mask_or_seg) || isnumeric(mask_or_seg)) && numel(mask_or_seg) == N
    mode = 'mask';
    m = mask_or_seg(:);
    if ~islogical(m)
        if ~all(m == 0 | m == 1)
            error('dlc_fix_predict:mask', 'A numeric mask may only contain 0 and 1.');
        end
        m = (m == 1);
    end
else
    error('dlc_fix_predict:input', ...
        'mask_or_seg must be a mask with one value per frame, or a segment structure.');
end

% ---- build / update segments ---------------------------------------------
switch mode
    case 'full'
        if isempty(jump_thresh), jump_thresh = DLC.auto_jump_threshold(x, y); end
        if isempty(win_width),   win_width = DLC.auto_window_width(x, y, jump_thresh); end
        seg = DLC.dlc_seg_build(x, y, jump_thresh, win_width);
        seg = propagate(seg, x, y, 1, numel(seg.start), P);

    case 'mask'
        if isempty(jump_thresh), jump_thresh = DLC.auto_jump_threshold(x, y); end
        seg = DLC.dlc_seg_build(x, y, jump_thresh, win_width, find(diff(m) ~= 0));
        good = m(seg.start);
        seg.flag(good)  = SEED;
        seg.flag(~good) = REJECT;
        seg.round(:) = 0;
        seg.err(:) = NaN;

    case 'seg'
        seg = check_seg(mask_or_seg, N);
        if ~isempty(jump_thresh), seg.jump_thresh = jump_thresh; end
        if isnan(seg.jump_thresh)
            seg.jump_thresh = DLC.auto_jump_threshold(x, y);
        end
        if ~isempty(win_width), seg.win_width = win_width; end
        M = numel(seg.start);
        region = false(M, 1);

        newIdx = find(seg.is_new);
        if ~isempty(newIdx)
            if any(seg.flag(newIdx) == 0) && isnan(seg.win_width)
                seg.win_width = DLC.auto_window_width(x, y, seg.jump_thresh);
            end
            % region: between nearest original (non-new) seeds
            isOrigSeed = (seg.flag == SEED) & ~seg.is_new;
            for k = newIdx'
                L = find(isOrigSeed(1:k-1), 1, 'last');
                if isempty(L), L = 0; end
                R = find(isOrigSeed(k+1:end), 1, 'first');
                if isempty(R), R = M + 1; else, R = R + k; end
                region(L+1:R-1) = true;
            end
            % apply the edits
            for k = newIdx'
                if seg.flag(k) > 0
                    seg.flag(k) = SEED;
                elseif seg.flag(k) < 0
                    seg.flag(k) = REJECT;
                elseif seg.len(k) >= seg.win_width
                    seg.flag(k) = SEED;
                end
                if seg.flag(k) ~= 0, seg.round(k) = 0; else, seg.round(k) = NaN; end
                seg.err(k) = NaN;
            end
            % reset everything else in the region that is not locked
            rs = region & ~seg.is_new & seg.flag ~= REJECT;
            seg.flag(rs) = 0;
            seg.round(rs) = NaN;
            seg.err(rs) = NaN;
            seg.is_new(:) = false;
            % propagate each region separately
            dr = diff([false; region; false]);
            a = find(dr == 1);
            b = find(dr == -1) - 1;
            for i = 1:numel(a)
                seg = propagate(seg, x, y, a(i), b(i), P);
            end
        end
        % undecided segments elsewhere (e.g. seeds-only input)
        if any(~region & seg.flag == 0)
            seg = propagate(seg, x, y, 1, M, P);
        end
end

% ---- conflicts and suggestions --------------------------------------------
seg = find_conflicts(seg, x, y, P);

% ---- output ----------------------------------------------------------------
mask = DLC.dlc_seg_mask(seg);
g = mask & isfinite(x) & isfinite(y);
if ~any(g)
    warning('dlc_fix_predict:noGood', 'No good frames; returning the raw trace.');
    x_fix = x; y_fix = y;
else
    [x_fix, y_fix] = interp_hold((1:N)', x, y, g);
end

if visualize
    plot_result(x, y, x_fix, y_fix, seg);
end
end

% ==========================================================================
function seg = propagate(seg, x, y, a, b, P)
% Progressive propagation, changing only undecided segments a..b. Segments
% outside a..b keep their flags and act as fixed neighbours.
GOOD = 1; BAD = -1; QUEST = -2;
F = seg.flag; rnd = seg.round; er = seg.err;
S = seg.start; E = seg.stop; L = seg.len;
M = numel(F);
thr = seg.jump_thresh;
K = P.CHECK_FRAMES;

inR = false(M, 1); inR(a:b) = true;
if a > 1, fa = S(a-1); else, fa = 1; end       % frames used for the
if b < M, fb = E(b+1); else, fb = numel(x); end % interpolation reference
fr = (fa:fb)';
xr = nan(size(fr)); yr = xr;

r = 0; growing = true; recheckQ = true;
while r <= M + 1                                 % hard stop, never reached
    r = r + 1;
    [lf, rf] = neighbours(F);
    if growing
        % 1. undecided next to good -> bad
        sel = inR & (F == 0 | F == QUEST) & (lf > 0 | rf > 0);
        F(sel) = BAD; rnd(sel) = r; er(sel) = NaN;
        [lf, rf] = neighbours(F);
    end
    % 2. undecided next to bad/questionable/locked -> candidates.
    %    Questionable ones are only rechecked when the reference changed.
    und = (F == 0) | (recheckQ & F == QUEST);
    cand = find(inR & und & (lf < 0 | rf < 0));
    if isempty(cand), break; end

    if growing
        g = repelem(F > 0, L);
        g = g(fr) & isfinite(x(fr)) & isfinite(y(fr));
        [xr, yr] = interp_hold(fr, x, y, g);
    end

    e = nan(numel(cand), 1);
    for i = 1:numel(cand)
        k = cand(i);
        ev = [];
        if lf(k) < 0
            idx = (S(k) : min(E(k), S(k) + K - 1))';
            ev(end+1) = median(hypot(x(idx) - xr(idx-fa+1), y(idx) - yr(idx-fa+1))); %#ok<AGROW>
        end
        if rf(k) < 0
            idx = (max(S(k), E(k) - K + 1) : E(k))';
            ev(end+1) = median(hypot(x(idx) - xr(idx-fa+1), y(idx) - yr(idx-fa+1))); %#ok<AGROW>
        end
        if any(isnan(ev)), e(i) = NaN; else, e(i) = max(ev); end
    end

    % accept closest matches first; never two neighbours in one round
    pass = e < thr;
    acc = false(M, 1);
    [~, ord] = sort(e);
    for i = ord'
        if ~pass(i), continue; end
        k = cand(i);
        if (k > 1 && acc(k-1)) || (k < M && acc(k+1)), continue; end
        acc(k) = true;
    end
    newF = QUEST * ones(numel(cand), 1);
    newF(acc(cand)) = GOOD;
    chg = F(cand) ~= newF;
    F(cand) = newF;
    rnd(cand(chg)) = r;
    er(cand) = e;

    growing = any(acc);
    recheckQ = growing;
    if ~growing && ~any(chg), break; end
end
seg.flag = F; seg.round = rnd; seg.err = er;
end

% ==========================================================================
function seg = find_conflicts(seg, x, y, P)
good = seg.flag > 0;
M = numel(good);
seg.conflict   = good(1:M-1) & good(2:M);
seg.suggestion = repmat({''}, M - 1, 1);
seg.suggest_at = nan(M - 1, 1);
for k = find(seg.conflict)'
    [seg.suggestion{k}, seg.suggest_at(k)] = suggest(seg, k, x, y, P);
end
end

function [s, at] = suggest(seg, k, x, y, P)
thr = seg.jump_thresh;
a = seg.stop(k); b = seg.start(k + 1);          % frames either side of jump
v = [x(b) - x(a), y(b) - y(a)];
nv = hypot(v(1), v(2));

% hidden jump: a 1..HIDDEN_LAGS frame displacement inside either side that
% cancels the detected jump (out-and-back with an undetected half), with
% the label staying at the wrong place between the two
best = Inf; bestAt = NaN;
sides = [seg.start(k), a; b, seg.stop(k + 1)];
for sd = 1:2
    f0 = sides(sd, 1); f1 = sides(sd, 2);
    for q = 1:P.HIDDEN_LAGS
        t = (f0 : f1 - q)';
        if isempty(t), continue; end
        c = hypot(v(1) + x(t+q) - x(t), v(2) + y(t+q) - y(t)) / nv;
        % ...and the label must stay where it went: the far side of the
        % hidden step matches the far side of the detected jump
        stay = hypot(x(t) - x(b), y(t) - y(b)) < thr & ...
               hypot(x(t+q) - x(a), y(t+q) - y(a)) < thr;
        c(~stay) = Inf;
        [cm, i] = min(c);
        if cm < best
            best = cm;
            t0 = t(i);
            st = hypot(diff(x(t0:t0+q)), diff(y(t0:t0+q)));
            [~, j] = max(st);
            bestAt = t0 + j - 1;                % split after this frame
        end
    end
end
if best < P.CANCEL_TOL
    s = 'split'; at = bestAt;
    return;
end

% false jump: near threshold, and motion continues in the jump direction
if nv < P.MERGE_RATIO * thr
    cont = false;
    mB = min(P.MERGE_FRAMES, seg.stop(k + 1) - b);
    if mB > 0
        cont = cont || same_direction(v, [x(b+mB) - x(b), y(b+mB) - y(b)]);
    end
    mA = min(P.MERGE_FRAMES, a - seg.start(k));
    if mA > 0
        cont = cont || same_direction(v, [x(a) - x(a-mA), y(a) - y(a-mA)]);
    end
    if cont
        s = 'merge'; at = a;                    % remove the jump after frame a
        return;
    end
end
s = 'review'; at = NaN;
end

function tf = same_direction(v, D)
nv = hypot(v(1), v(2)); nD = hypot(D(1), D(2));
tf = nD >= 0.25 * nv && (v * D') / (nv * nD) > 0.5;
end

% ==========================================================================
function [lf, rf] = neighbours(F)
lf = [NaN; F(1:end-1)];
rf = [F(2:end); NaN];
end

function [xr, yr] = interp_hold(fr, x, y, g)
% pchip through good frames fr(g); hold the nearest good value outside.
xr = nan(size(fr)); yr = xr;
gi = fr(g);
if isempty(gi), return; end
if numel(gi) == 1
    xr(:) = x(gi); yr(:) = y(gi);
    return;
end
xr = interp1(gi, x(gi), fr, 'pchip', NaN);
yr = interp1(gi, y(gi), fr, 'pchip', NaN);
lo = fr < gi(1);  xr(lo) = x(gi(1));   yr(lo) = y(gi(1));
hi = fr > gi(end); xr(hi) = x(gi(end)); yr(hi) = y(gi(end));
end

function seg = check_seg(seg, N)
need = {'start', 'stop', 'flag'};
for f = need
    if ~isfield(seg, f{1})
        error('dlc_fix_predict:seg', 'Segment structure needs field "%s".', f{1});
    end
end
seg.start = seg.start(:); seg.stop = seg.stop(:); seg.flag = double(seg.flag(:));
M = numel(seg.start);
if seg.start(1) ~= 1 || seg.stop(end) ~= N || ...
        any(seg.start(2:end) ~= seg.stop(1:end-1) + 1) || any(seg.stop < seg.start)
    error('dlc_fix_predict:seg', ...
        'Segments must be contiguous and cover frames 1..%d.', N);
end
seg.len = seg.stop - seg.start + 1;
defaults = {'is_new', false(M, 1); 'round', nan(M, 1); 'err', nan(M, 1); ...
            'conflict', false(M-1, 1); 'suggestion', repmat({''}, M-1, 1); ...
            'suggest_at', nan(M-1, 1)};
for i = 1:size(defaults, 1)
    if ~isfield(seg, defaults{i, 1}) || numel(seg.(defaults{i, 1})) ~= numel(defaults{i, 2})
        seg.(defaults{i, 1}) = defaults{i, 2};
    end
end
seg.is_new = logical(seg.is_new(:));
seg.n_frames = N;
if ~isfield(seg, 'jump_thresh') || isempty(seg.jump_thresh), seg.jump_thresh = NaN; end
if ~isfield(seg, 'win_width')   || isempty(seg.win_width),   seg.win_width = NaN;   end
end

% ==========================================================================
function plot_result(x, y, x_fix, y_fix, seg)
N = numel(x); t = (1:N)';
fe = repelem(seg.flag, seg.len);
figure('Color', 'w'); hold on;
plot(t, [x y], '-', 'Color', [0.7 0.7 0.7]);
plot(t, [x_fix y_fix], 'k-', 'LineWidth', 1);
styles = {2, [0 0.6 0], '.', 'seed'; 1, [0 0.45 0.9], '.', 'good (propagated)'; ...
          -1, [0.85 0 0], 'x', 'bad'; -2, [0.8 0 0.8], '^', 'questionable'; ...
          -3, [0.5 0 0], 's', 'rejected'; 0, [0.5 0.5 0.5], 'o', 'unflagged'};
h = []; lab = {};
for i = 1:size(styles, 1)
    sel = fe == styles{i, 1};
    if ~any(sel), continue; end
    xs = x; ys = y; xs(~sel) = NaN; ys(~sel) = NaN;
    hh = plot(t, [xs ys], styles{i, 3}, 'Color', styles{i, 2}, 'MarkerSize', 4);
    h(end+1) = hh(1); lab{end+1} = styles{i, 4}; %#ok<AGROW>
end
yl = ylim;
for k = find(seg.conflict)'
    tc = seg.stop(k) + 0.5;
    plot([tc tc], yl, 'r-', 'LineWidth', 1.5);
    text(tc, yl(2), [' ' seg.suggestion{k}], 'Color', 'r', ...
        'VerticalAlignment', 'top', 'Rotation', 90);
end
legend(h, lab, 'Location', 'best');
xlabel('frame'); ylabel('x, y');
title(sprintf('%d segments, %d good (%d seeds), %d conflicts', numel(seg.flag), ...
    sum(seg.flag > 0), sum(seg.flag == 2), sum(seg.conflict)));
end
