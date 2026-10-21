function load_session(fig)
% shared.load_session(fig)
% Load a StepSync session .mat file. fig: window that shows alerts.

    data = shared.SessionData.instance();
    [filename, path] = uigetfile(fullfile(data.defaultPath, '*.mat'), 'Load .mat file');
    if filename ==0, return; end
    filename = fullfile(path, filename);
    savedata = load(filename);

    required = {'defaultPath','frameRate','currentTime','currentZoom','figures'};
    if ~all(isfield(savedata, required))
        uialert(fig, 'This is not a StepSync session file.', 'Load error'); return;
    end
    savedata = shared.migrate_session_time(savedata);
    validateattributes(savedata.frameRate, {'numeric'}, {'scalar','finite','nonnegative'});
    validateattributes(savedata.currentTime, {'numeric'}, {'scalar','finite','nonnegative'});
    validateattributes(savedata.currentZoom, {'numeric'}, {'vector','numel',2,'finite'});
    if savedata.currentZoom(2) <= savedata.currentZoom(1)
        error('StepSync:zoom', 'Saved zoom limits must be increasing.');
    end
    % close without per-window prompts and without resetting the session
    data.closingAll = true;
    restore = onCleanup(@()stopClosingAll(data));
    for name = {'gait','video','dlc','emg'}
        if isfield(data.fig, name{1}) && isgraphics(data.fig.(name{1}), 'figure')
            close(data.fig.(name{1}));
        end
        data.(name{1}) = struct();
    end
    clear restore
    data.fig = struct();
    data.defaultPath = savedata.defaultPath;
    data.frameRate = savedata.frameRate;
    data.currentTime = savedata.currentTime;
    data.currentZoom = savedata.currentZoom;
    modules = fieldnames(savedata.figures);
    for k = 1:length(modules)
        module = modules{k};

        % restore figure positions
        shared.open_module(module);
        data.fig.(module).Position = savedata.figures.(module).Position;

        % restore data and parameters
        if isfield(savedata, module)
            savedata.(module).hd = shared.set_param(data.(module).hd, savedata.(module).parameters);
            data.(module) = rmfield(savedata.(module), 'parameters');
        end

    end
    % Populate legacy trigger metadata before any viewer receives InfoChanged.
    if data.has('emg') && isfield(data.emg,'trigger')
        intervals = diff(data.emg.trigger.time);
        intervals = intervals(isfinite(intervals) & intervals>0);
        data.emg.trigger.freq = NaN;
        if ~isempty(intervals), data.emg.trigger.freq = 1/median(intervals); end
        data.emg.trigger.number = numel(data.emg.trigger.time);
    end
    % activate data display in each module
    % (gait recalculates on InfoChanged and then publishes GaitChanged)
    notify(data, 'InfoChanged');
    notify(data, 'EMGChanged');
    data.notifyDLC('load');
    % Assignments above do not emit events; synchronize restored views explicitly.
    data.currentTime = savedata.currentTime;
    data.currentZoom = savedata.currentZoom;
    notify(data, 'TimeChanged');
    notify(data, 'ZoomChanged');
end

function stopClosingAll(data)
    if isvalid(data), data.closingAll = false; end
end
