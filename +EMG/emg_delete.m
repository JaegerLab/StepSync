function emg = emg_delete(emg, label)
% emg = EMG.emg_delete(emg, label)
% Remove one EMG data type ('Raw' or 'Processed k'). The remaining processed
% types are renumbered; metadata (trigger, channels, ...) is kept.

    if ~any(strcmp(label, EMG.emg_types(emg)))
        error('EMG:type', 'No EMG data of type "%s".', label);
    end
    if strcmp(label, 'Raw')
        emg = rmfield(emg, 'raw');
    else
        emg.processed(sscanf(label, 'Processed %d')) = [];
    end
end
