function src = emg_source(emg, label)
% src = EMG.emg_source(emg, label)
% Data of one EMG type: struct with data (samples x channels), t, sample_rate
% (and parameters for processed data). label: 'Raw' or 'Processed k'.

    if ~any(strcmp(label, EMG.emg_types(emg)))
        error('EMG:type', 'No EMG data of type "%s".', label);
    end
    if strcmp(label, 'Raw')
        src = emg.raw;
    else
        src = emg.processed(sscanf(label, 'Processed %d'));
    end
end
