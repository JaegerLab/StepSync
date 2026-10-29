function hfig = StepSync(defaultPath)
% StepSync(defaultPath)
% Launcher with one button per module. It closes when a module window
% opens. If module windows are open already, they are brought to front
% instead. defaultPath: start folder of the file dialogs.

    data = shared.SessionData.instance();
    if nargin >= 1
        data.defaultPath = defaultPath;
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
        'Tag', shared.MenuBar.LauncherTag, 'CloseRequestFcn', @onLauncherClose);
    shared.MenuBar(fig, {'Open', []; 'Save', []}, false);
    if nargout == 1, hfig = fig; end

    % Data Launcher Buttons
    grid1 = uigridlayout(fig, [2 2], 'Padding', [20 20 20 20]);
    uibutton(grid1, 'Text', 'Video', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
    uibutton(grid1, 'Text', 'Ephys', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
    uibutton(grid1, 'Text', 'Pose', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
    uibutton(grid1, 'Text', 'Gait', 'ButtonPushedFcn', @(src,~)shared.open_module(src.Text));
end

% Closed by the user (opening a module deletes the launcher without this):
% with no module window open, end the session as Exit all does.
function onLauncherClose(src, ~)
    delete(src);
    if isempty(shared.open_windows())
        delete(shared.SessionData.instance());
    end
end
