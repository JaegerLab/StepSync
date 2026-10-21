function save_emg(filename, emg, labels)
% EMG.save_emg(filename, emg, labels)
% Write EMG data types to a .mat file (-v7.3):
%   fileFormat = 'StepSync EMG', formatVersion = 1
%   emg          metadata (trigger, channels, ...) without data or UI handles
%   raw          if 'Raw' is in labels
%   processed1.. the processed types in labels, numbered in that order
% labels: cellstr from EMG.emg_types.

    out = struct();
    out.fileFormat = 'StepSync EMG';
    out.formatVersion = 1;
    out.emg = rmfield(emg, intersect(fieldnames(emg), {'hd', 'temp', 'raw', 'processed'}));
    n = 0;
    for k = 1:numel(labels)
        src = EMG.emg_source(emg, labels{k});
        if strcmp(labels{k}, 'Raw')
            out.raw = src;
        else
            n = n + 1;
            out.(sprintf('processed%d', n)) = src;
        end
    end
    save(filename, '-struct', 'out', '-v7.3');
end
