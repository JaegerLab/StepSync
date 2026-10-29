function remember_position(module, fig)
% shared.remember_position(module, fig)
% Keep a closing module window's position in the MATLAB preferences, so the
% next window of that module opens there (see shared.window_position), also
% after MATLAB restarts. A minimized window keeps the previous position.

    if ~isgraphics(fig, 'figure') || strcmp(fig.WindowState, 'minimized'), return; end
    saved = struct();
    if ispref('StepSync', 'windowPositions')
        saved = getpref('StepSync', 'windowPositions');
        if ~isstruct(saved), saved = struct(); end
    end
    saved.(module) = fig.Position;
    setpref('StepSync', 'windowPositions', saved);
end
