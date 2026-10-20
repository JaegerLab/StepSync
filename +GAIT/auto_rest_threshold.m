function [threshold, info] = auto_rest_threshold(speed, fs)
%AUTO_REST_THRESHOLD Estimate near-zero speed without a user-facing parameter.
% Smoothed speed identifies sustained resting windows. Their original speed
% samples set the threshold (75th percentile). No identifiable rest -> NaN.
validateattributes(fs, {'numeric'}, {'scalar','finite','positive'});
speed = speed(:);
threshold = NaN;
info = struct('status','No distinct resting-speed cluster', 'restMask',false(size(speed)));
window = max(3, round(0.15*fs));
margin = ceil(window/2)+3; % exclude smoothing/transient boundary zeros
valid = isfinite(speed) & speed >= 0;
if numel(speed) <= 2*margin+window, info.status = 'Trace too short'; return; end
valid(1:margin) = false; valid(end-margin+1:end) = false;
filtered = speed; filtered(~valid) = NaN;
smoothed = movmean(filtered, window, 'omitnan', 'Endpoints','shrink');
v = smoothed(valid);
if numel(v) < 30 || max(v) <= min(v), return; end
% Compress large movements so a small resting mode remains visible.
scale = pct(v(v>0), 50);
if ~isfinite(scale) || scale <= 0, scale = 1; end
z = log1p(smoothed/scale);
hi = pct(z(valid),99.5);
if ~isfinite(hi) || hi <= 0, return; end
edges = linspace(0,hi,65);
counts = histcounts(z(valid),edges);
counts = conv(counts,[1 2 3 2 1]/9,'same');
peaks = find(counts > [0 counts(1:end-1)] & counts >= [counts(2:end) 0]);
peaks = peaks(counts(peaks) >= 0.02*max(counts));
cut = NaN;
for a = 1:numel(peaks)
    for b = a+1:numel(peaks)
        lo = peaks(a); up = peaks(b);
        if up-lo < 4, continue; end
        [depth,j] = min(counts(lo+1:up-1));
        valley = lo+j;
        if depth > 0.5*min(counts([lo up])), continue; end
        if sum(counts(1:valley)) < 0.05*sum(counts), continue; end
        cut = edges(valley+1); break;
    end
    if isfinite(cut), break; end
end
if ~isfinite(cut), return; end
candidate = valid & z <= cut;
d = diff([false;candidate;false]);
starts = find(d==1); stops = find(d==-1)-1;
for k = 1:numel(starts)
    % Exclude transitions, then require a sustained interior.
    a = starts(k)+ceil(window/2); b = stops(k)-ceil(window/2);
    if b-a+1 >= window, info.restMask(a:b) = true; end
end
if nnz(info.restMask)<10, info.status = 'No sustained resting windows'; return; end
threshold = pct(speed(info.restMask),75);
info.status = 'Estimated from sustained resting windows';
end

function value = pct(x,p)
x = sort(x(isfinite(x)));
if isempty(x), value = NaN; return; end
position = 1+(numel(x)-1)*p/100;
a = floor(position); b = ceil(position);
value = x(a)+(position-a)*(x(b)-x(a));
end
