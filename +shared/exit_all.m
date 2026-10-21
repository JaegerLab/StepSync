function exit_all(confirm, fig)
% shared.exit_all(confirm, fig)
% Close every StepSync window, then reset the session so the next start has
% no leftover frame rate, time, zoom or path.
%   confirm  ask once before closing (default true); module windows do not ask
%   fig      window that shows the question

    if nargin < 1, confirm = true; end
    if confirm
        answer = uiconfirm(fig, 'Close all StepSync windows?', 'Exit all', ...
            'Options', {'Exit all', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, ...
            'Icon', 'warning');
        if ~strcmp(answer, 'Exit all'), return; end
    end

    data = shared.SessionData.instance();
    data.closingAll = true;
    windows = shared.open_windows();
    windows = windows(~[windows.isSub]);   % modules close their sub-windows
    for k = 1:numel(windows)
        if ~isgraphics(windows(k).fig), continue; end
        try
            close(windows(k).fig);
        catch ME
            warning(ME.identifier, '%s', ME.message);
            delete(windows(k).fig);
        end
    end
    delete(findall(groot, 'Type', 'figure', 'Tag', shared.MenuBar.LauncherTag));
    delete(data);
end
