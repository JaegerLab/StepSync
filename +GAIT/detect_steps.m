function steps = detect_steps(trace, mask, threshold, minInterval, nearZero)
%DETECT_STEPS Calculate one paw/trace; indices always refer to original frames.
% steps = GAIT.detect_steps(trace, mask, threshold, minInterval)
% steps = GAIT.detect_steps(trace, mask, threshold, minInterval, nearZero)
%
%  trace:       paw x, y or speed, one value per frame
%  mask:        logical, false for excluded frames
%  threshold:   threshold, in the units of trace
%  minInterval: minimum distance between events (frames); also the search
%               range for onset/offset
%  nearZero:    rest level for onset/offset (default NaN: none found)
% steps: struct of frame indices: rising, falling, onset, offset, peak,
%        valley, masked (first frame of each masked period).
% See docs/functions.md.

if nargin<5, nearZero = NaN; end
trace = trace(:);
mask = logical(mask(:));
if numel(mask) ~= numel(trace), error('GAIT:maskSize', 'Mask and trace sizes differ.'); end
validateattributes(minInterval, {'numeric'}, {'scalar','integer','positive','finite'});
trace(~mask) = NaN;
steps = struct('rising', [], 'falling', [], 'onset', [], 'offset', [], ...
    'peak', [], 'valley', [], 'masked', find(diff(~mask)==1)+1);
if ~isfinite(threshold) || ~any(isfinite(trace)), return; end
steps.rising = find(trace(1:end-1)<=threshold & trace(2:end)>threshold);
steps.falling = find(trace(1:end-1)>threshold & trace(2:end)<=threshold)+1;
onset = nan(size(steps.rising));
offset = nan(size(steps.falling));
for k = 1:numel(onset)
    f = steps.rising(k);
    range = max(1, f-minInterval):f;
    % Do not search across a masked/missing interval.
    gap = find(~isfinite(trace(range)), 1, 'last');
    if ~isempty(gap), range = range(gap+1:end); end
    j = find(trace(range) <= nearZero, 1, 'last');
    if ~isempty(j), onset(k) = range(j); end
end
for k = 1:numel(offset)
    f = steps.falling(k);
    range = f:min(numel(trace), f+minInterval);
    gap = find(~isfinite(trace(range)), 1, 'first');
    if ~isempty(gap), range = range(1:gap-1); end
    j = find(trace(range) <= nearZero, 1, 'first');
    if ~isempty(j), offset(k) = range(j); end
end
steps.onset = unique(onset(isfinite(onset)));
steps.offset = unique(offset(isfinite(offset)));
% Process finite runs independently so peaks cannot bridge excluded periods.
finite = isfinite(trace);
d = diff([false; finite; false]);
starts = find(d==1); stops = find(d==-1)-1;
prominence = std(trace, 'omitnan');
for k = 1:numel(starts)
    range = starts(k):stops(k);
    if numel(range) < 3, continue; end
    distance = min(minInterval, numel(range)-2);
    [value, idx] = findpeaks(trace(range), 'MinPeakProminence', prominence, 'MinPeakDistance', distance);
    keep = value >= threshold;
    steps.peak = [steps.peak; starts(k)-1+idx(keep)]; %#ok<AGROW>
    
    [~, idx] = findpeaks(-trace(range), 'MinPeakProminence', prominence, 'MinPeakDistance', distance);
    idx = idx(trace(range(idx)) <= threshold);
    steps.valley = [steps.valley; starts(k)-1+idx]; %#ok<AGROW>
end
end
