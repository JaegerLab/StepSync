function t = frame_times(nFrames, frameRate, triggerTimes)
%FRAME_TIMES Frame times on the EMG clock; a one-record tail mismatch is allowed.
validateattributes(nFrames, {'numeric'}, {'scalar','integer','nonnegative'});
validateattributes(frameRate, {'numeric'}, {'scalar','finite','positive'});
if nargin < 3 || isempty(triggerTimes)
    t = (1:nFrames)'/frameRate;
    return;
end
triggerTimes = triggerTimes(:);
validateattributes(triggerTimes, {'numeric'}, {'vector','finite','increasing'});
if abs(numel(triggerTimes)-nFrames) > 1
    error('StepSync:timing:countMismatch', ...
        'Found %d frames and %d camera TTL pulses; automatic alignment requires counts within one.', ...
        nFrames, numel(triggerTimes));
end
t = nan(nFrames,1);
n = min(nFrames,numel(triggerTimes));
t(1:n) = triggerTimes(1:n);
% An unmatched final frame has no measured time and is excluded from analysis.
end
