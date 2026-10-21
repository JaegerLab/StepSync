function hfig = StepSync(default_path)
% StepSync(default_path)
% Launcher with one button per module. It closes when a module window
% opens. If module windows are open already, they are brought to front
% instead. default_path: start folder of the file dialogs.

    data = shared.SessionData.instance();
    if nargin >= 1
        data.defaultPath = default_path;
    elseif isempty(data.defaultPath)
        data.defaultPath = 'E:\Openfield\data';
    end
    if nargout == 1, hfig = []; end
    if ~isempty(shared.open_windows())
        shared.bring_all_to_front();
        return;
    end
    launcher = findall(groot, 'Type', 'figure', 'Tag', shared.MenuBar.LauncherTag);
    if ~isempty(launcher)
        figure(launcher(1));
        if nargout == 1, hfig = launcher(1); end
        return;
    end

    fig = uifigure('Name', 'StepSync', 'Position', [100 100 400 200], ...
        'Tag', shared.MenuBar.LauncherTag);
    shared.MenuBar(fig, {'Open', []; 'Save', []}, false);
    if nargout == 1, hfig = fig; end

    % turn off "ButtonDownFcn" warning when selecting tools
    s = warning('off', 'MATLAB:modes:mode:InvalidPropertySet');
    cleanup = onCleanup(@() warning(s)); % restore warning after quitting

    % Data Launcher Buttons
    grid1 = uigridlayout(fig, [2 2], 'Padding', [20 20 20 20]);
    uibutton(grid1, 'Text', 'Video', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
    uibutton(grid1, 'Text', 'EMG', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
    uibutton(grid1, 'Text', 'DLC', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
    uibutton(grid1, 'Text', 'Gait', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
end
