function labels = emg_types(emg)
% labels = EMG.emg_types(emg)
% Data types in data.emg, as shown in the EMG viewer's dropdown:
% 'Raw' if emg.raw has data, then 'Processed 1' .. 'Processed N'.

    labels = {};
    if isfield(emg, 'raw') && ~isempty(emg.raw) && ~isempty(emg.raw.data)
        labels{end+1} = 'Raw';
    end
    if isfield(emg, 'processed')
        for k = 1:numel(emg.processed)
            labels{end+1} = sprintf('Processed %d', k); %#ok<AGROW>
        end
    end
end
