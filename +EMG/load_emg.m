function emg = load_emg(filename, names)
% emg = EMG.load_emg(filename, names)
% Read an EMG .mat file written by EMG.save_emg, loading only the data
% variables in names (from EMG.emg_file_contents). Returns data.emg without
% UI handles: the metadata, raw (if loaded) and processed (in file order).

    f = load(filename, 'emg', names{:});
    emg = f.emg;
    if isfield(f, 'raw')
        emg.raw = struct('data', f.raw.data, 't', f.raw.t, 'sample_rate', f.raw.sample_rate);
    end
    emg.processed = struct('data', {}, 't', {}, 'sample_rate', {}, 'parameters', {});
    for k = 1:numel(names)
        if ~startsWith(names{k}, 'processed'), continue; end
        p = f.(names{k});
        emg.processed(end+1) = struct('data', p.data, 't', p.t, ...
            'sample_rate', p.sample_rate, 'parameters', p.parameters);
    end
end
