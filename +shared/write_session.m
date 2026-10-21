function write_session(filename, modules)
% shared.write_session(filename, modules)
% Write a session .mat file (-v7.3) with the given modules.
%   modules: cellstr of modules with an open window, e.g. {'dlc', 'gait'}
% Each module is saved with its window position and, if it has data, its
% data and widget values (see shared.get_param).

    data = shared.SessionData.instance();
    out = struct();
    out.fileFormat = 'StepSync session';
    out.formatVersion = 3;
    out.frameRate = data.frameRate;
    out.currentTime = data.currentTime;
    out.currentZoom = data.currentZoom;
    out.figures = struct();
    for k = 1:numel(modules)
        module = modules{k};
        out.figures.(module).Position = data.fig.(module).Position;
        if data.has(module)
            saved = rmfield(data.(module), 'hd');
            saved.parameters = shared.get_param(data.(module).hd);
            out.(module) = saved;
        end
    end
    save(filename, '-struct', 'out', '-v7.3');
end
