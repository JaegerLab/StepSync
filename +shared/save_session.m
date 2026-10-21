function save_session(fig)
% shared.save_session(fig)
% Save the session as a .mat file. fig: window that shows progress and alerts.

    data = shared.SessionData.instance();
    [filename, path] = uiputfile(fullfile(data.defaultPath, '*.mat'), 'Save As');
    if filename ==0, return; end

    filename = fullfile(path, filename);
    progbar = uiprogressdlg(fig,'Title','Saving', ...
        'Message','Saving', ...
        'Indeterminate','on');

    timebaseVersion = 2;
    defaultPath = data.defaultPath;
    frameRate = data.frameRate;
    currentTime = data.currentTime;
    currentZoom = data.currentZoom;
    save(filename,"defaultPath","frameRate","currentTime","currentZoom","timebaseVersion", "-v7.3");

    % ===== change handle to parameters ========
    % save figure positions
    modules = fieldnames(data.fig);
    figures = struct();
    for k = 1:length(modules)
        module = modules{k};
        figures.(module).Position = data.fig.(module).Position;
    end
    save(filename,"figures", "-append");
    % save values from ui edits and listboxes
    if data.has('video')
        progbar.Message = 'Saving Video';
        video = rmfield(data.video, 'hd');
        video.parameters = shared.get_param(data.video.hd);
        save(filename,"video", "-append");
    end
    if data.has('emg')
        progbar.Message = 'Saving EMG';
        emg = rmfield(data.emg, {'hd'});
        emg.parameters = shared.get_param(data.emg.hd);
        save(filename,"emg", "-append");
    end
    if data.has('dlc')
        progbar.Message = 'Saving DLC';
        dlc = rmfield(data.dlc, {'hd'});
        dlc.parameters = shared.get_param(data.dlc.hd);
        save(filename,"dlc", "-append");
    end
    if data.has('gait')
        progbar.Message = 'Saving Gait';
        gait = rmfield(data.gait, {'hd'});
        gait.parameters = shared.get_param(data.gait.hd);
        save(filename,"gait", "-append");
    end

    close(progbar)
    uialert(fig, ['Data saved in ' filename], 'Success','Icon','success');
end
