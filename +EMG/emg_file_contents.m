function [names, bytes] = emg_file_contents(filename)
% [names, bytes] = EMG.emg_file_contents(filename)
% Data variables of an EMG .mat file written by EMG.save_emg, without
% loading them: names = {'raw', 'processed1', ...}, bytes = their sizes.
% Errors: EMG:file:format (not a StepSync EMG file), EMG:file:newer.

    VERSION = 1;
    [~, name, ext] = fileparts(filename);
    name = [name ext];
    info = whos('-file', filename);
    vars = {info.name};
    if ~all(ismember({'fileFormat', 'formatVersion', 'emg'}, vars))
        error('EMG:file:format', '%s is not a StepSync EMG file.', name);
    end
    f = load(filename, 'fileFormat', 'formatVersion');
    if ~isequal(f.fileFormat, 'StepSync EMG')
        error('EMG:file:format', '%s is not a StepSync EMG file.', name);
    end
    if f.formatVersion > VERSION
        error('EMG:file:newer', '%s was saved by a newer StepSync (format %g; this version reads format %d).', ...
            name, f.formatVersion, VERSION);
    end

    processed = regexp(vars, '^processed(\d+)$', 'tokens', 'once');
    isProcessed = ~cellfun(@isempty, processed);
    numbers = cellfun(@(c)str2double(c{1}), processed(isProcessed));
    [~, order] = sort(numbers);
    idx = find(isProcessed);
    idx = [find(strcmp(vars, 'raw')), idx(order)];
    names = vars(idx);
    bytes = [info(idx).bytes];
end
