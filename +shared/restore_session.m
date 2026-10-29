function restore_session(saved)
% shared.restore_session(saved)
% Replace all module windows with the modules of a session read by
% shared.read_session: close every module window without prompts, then
% reopen the saved modules with their positions, data and widget values.

    data = shared.SessionData.instance();
    % close without per-window prompts and without resetting the session
    data.closingAll = true;
    restore = onCleanup(@()stopClosingAll(data));
    for name = {'gait','video','pose','ephys'}
        if isfield(data.fig, name{1}) && isgraphics(data.fig.(name{1}), 'figure')
            close(data.fig.(name{1}));
        end
        data.(name{1}) = struct();
    end
    clear restore
    data.fig = struct();
    data.frameRate = saved.frameRate;
    data.currentTime = saved.currentTime;
    data.currentZoom = saved.currentZoom;
    modules = fieldnames(saved.figures);
    for k = 1:length(modules)
        module = modules{k};

        % restore figure positions
        shared.open_module(module);
        data.fig.(module).Position = saved.figures.(module).Position;

        % restore data and parameters
        if isfield(saved, module)
            saved.(module).hd = shared.set_param(data.(module).hd, saved.(module).parameters);
            data.(module) = rmfield(saved.(module), 'parameters');
        end
    end
    % activate data display in each module
    % (gait recalculates on InfoChanged and then publishes GaitChanged)
    notify(data, 'InfoChanged');
    notify(data, 'EphysChanged');
    data.notifyPose('load');
    % Assignments above do not emit events, and redrawing may have changed the
    % zoom: synchronize restored views explicitly. Zoom first, because viewers
    % pan from their axis limits on TimeChanged.
    data.currentTime = saved.currentTime;
    data.currentZoom = saved.currentZoom;
    notify(data, 'ZoomChanged');
    notify(data, 'TimeChanged');
end

function stopClosingAll(data)
    if isvalid(data), data.closingAll = false; end
end
