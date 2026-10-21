function save_emg(filename, emg, labels, range)
% EMG.save_emg(filename, emg, labels, range)
% Write EMG data types to a .mat file (-v7.3):
%   fileFormat = 'StepSync EMG', formatVersion = 1
%   emg          metadata (trigger, channels, ...) without data or UI handles;
%                emg.time_range is the saved range ([] for the full length)
%   raw          if 'Raw' is in labels
%   processed1.. the processed types in labels, numbered in that order
% labels: cellstr from EMG.emg_types.
% range:  [] (default) for the full length, or [t1 t2]: only samples with
%         t1 <= t <= t2, times unchanged so they stay aligned with the trigger.

    if nargin < 4, range = []; end
    out = struct();
    out.fileFormat = 'StepSync EMG';
    out.formatVersion = 1;
    out.emg = rmfield(emg, intersect(fieldnames(emg), {'hd', 'temp', 'raw', 'processed'}));
    out.emg.time_range = range;
    n = 0;
    for k = 1:numel(labels)
        src = EMG.emg_source(emg, labels{k});
        if ~isempty(range)
            keep = src.t >= range(1) & src.t <= range(2);
            src.data = src.data(keep, :);
            src.t = src.t(keep);
        end
        if strcmp(labels{k}, 'Raw')
            out.raw = src;
        else
            n = n + 1;
            out.(sprintf('processed%d', n)) = src;
        end
    end
    save(filename, '-struct', 'out', '-v7.3');
end
