function fig = open_module(module)
% fig = shared.open_module(module)
% Open a module window, or bring it to the front if it is open, and close
% the launcher. module: 'video' | 'emg' | 'dlc' | 'gait' (any case).

    module = lower(module);
    data = shared.SessionData.instance();
    if isfield(data.fig, module) && isgraphics(data.fig.(module), 'figure')
        fig = data.fig.(module);
        figure(fig);
    else
        switch module
            case 'video', fig = VIDEO.video_viewer();
            case 'emg',   fig = EMG.emg_viewer();
            case 'dlc',   fig = DLC.dlc_viewer();
            case 'gait',  fig = GAIT.gait_viewer();
            otherwise
                error('StepSync:module', 'Unknown module: %s', module);
        end
    end
    delete(findall(groot, 'Type', 'figure', 'Tag', shared.MenuBar.LauncherTag));
end
