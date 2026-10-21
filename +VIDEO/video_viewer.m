function fig = video_viewer()
% App state

data = shared.SessionData.instance();

drawGUI();


function drawGUI()
    % Main UI figure with grid layout
    fig = uifigure('Name', 'Video Viewer', 'Position', [100 100 600 600], ...
        'CloseRequestFcn', @onClose);
    data.fig(1).video = fig;
    shared.MenuBar(fig, {'Open', @openVideo; 'Save', []});
    % for dragging markers
    fig.WindowButtonDownFcn   = @(src,evt)onMouseDown(src, evt);
    fig.WindowButtonMotionFcn = @(src,evt)onMouseMove(src, evt);
    fig.WindowButtonUpFcn     = @(src,evt)onMouseUp(src, evt);
    drawnow

    gl = uigridlayout(fig, [3, 2]);
    gl.RowHeight = {30, 40, '1x'};
    gl.ColumnWidth = {'1x', 100};
    gl.Padding = [10 10 10 10];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 8;

    hd = struct();

    % Row 1: frame info
    subgrid1 = uigridlayout(gl, [1 3], 'Padding', [0 0 0 0]);
    subgrid1.ColumnWidth = {'1x', 130, 100, 90};
    subgrid1.Layout.Row = 1; subgrid1.Layout.Column = 1;

        % subgrid1
        hd.info = uilabel(subgrid1, ...
            'Text', 'Info:', 'BackgroundColor','W');

        hd.frameRate = uieditfield(subgrid1, 'numeric', ...
            'Limits', [0 Inf], 'LowerLimitInclusive', 'off', 'Value', 1, ...
            'ValueDisplayFormat', 'FrameRate: %.2f Hz', ...
            'ValueChangedFcn', @(src,~)updateFrameRate(src.Value));

        hd.time = uieditfield(subgrid1, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueDisplayFormat', 'time: %.3f s', ...
            'ValueChangedFcn', @(src,~)data.setTime(src.Value));

        hd.frame = uieditfield(subgrid1, 'numeric', ...
            'Limits', [1 Inf], ...
            'RoundFractionalValues', true, ...
            'ValueDisplayFormat', 'frame: %d', ...
            'ValueChangedFcn', @manualFrameInput);

    subgrid2 = uigridlayout(gl, [1 2], 'Padding', [0 0 0 0]);
    subgrid2.Layout.Row = 1; subgrid2.Layout.Column = 2;

        hd.last = uibutton(subgrid2, 'Text', '<', ...
            'Tooltip','Ctrl+Click to change step size', ...
            'ButtonPushedFcn', @(src,evt)moveVideoFrame(-1));
        hd.next = uibutton(subgrid2, 'Text', '>', ...
            'Tooltip','Ctrl+Click to change step size', ...
            'ButtonPushedFcn', @(src,evt)moveVideoFrame(1));
    
    % Row 2: slider and play button
    hd.slider = uislider(gl, 'ValueChangedFcn', @sliderMoved);
    hd.slider.Layout.Row = 2; hd.slider.Layout.Column = 1;
    hd.play = uibutton(gl, 'Text', 'Play', 'ButtonPushedFcn', @togglePlay);
    hd.play.Layout.Row = 2; hd.play.Layout.Column = 2;

    % Row 3: axes for video
    ax = uiaxes(gl);
    ax.Layout.Row = 3; ax.Layout.Column = [1 2];
    ax.XTick = []; ax.YTick = [];

    % Timer for playback
    hd.timer = timer('ExecutionMode', 'fixedSpacing', ...
        'Period', 0.02, ...
        'TimerFcn', @timerRunning);

    hd.ax = ax;
    axis(hd.ax, 'image'); axis(hd.ax, 'off');
    hold(hd.ax, "on");

    % add listeners
    hd.timeListener = addlistener(data, 'TimeChanged', @(src, ~)updateVideoTime(src.currentTime));
    hd.infoListener = addlistener(data, 'InfoChanged', @(~,~)onInfoChanged());
    % DLC and gait changes only redraw markers; the frame is not re-read.
    hd.dlcListener = addlistener(data, 'DLCChanged', @(~,~)redrawMarkers());
    hd.gaitListener = addlistener(data, 'GaitChanged', @(~,~)redrawMarkers());

    data.video(1).hd = hd;
    notify(data, 'WindowsChanged');
end

function openVideo(~,~)
    hd = data.video.hd;
    [file, path] = uigetfile(fullfile(data.defaultPath, '*.mp4'), 'Open Video file');
    drawnow; figure(fig);
    if isequal(file, 0); return; end
    filename = fullfile(path, file);
    data.rememberPath(filename);
    stop(hd.timer);
    data.video.vid = VideoReader(filename);
    data.video.filename = filename;
    data.video.frameIdx = 1;

    data.video.hd = hd;

    data.video.frameRate = data.getFrameRate();
    hd.frameRate.Value = data.video.frameRate;

    updateInfo();
    updateVideoFrame(1);
    data.setTime(data.video.t(1));
    notify(data, 'InfoChanged');
end

% The title shows the source video.
function updateTitle()
    fig.Name = 'Video Viewer';
    if data.has('video') && isfield(data.video, 'filename')
        fig.Name = ['Video Viewer: ' data.video.filename];
    end
end

%% main == event response callback function
function updateVideoFrame(newFrameIdx)
    if ~data.has('video'), return; end
    hd = data.video.hd;
    frameRate = data.getFrameRate();
    if nargin == 0, newFrameIdx = data.video.frameIdx + 1; end
    lastMatched = find(isfinite(data.video.t),1,'last');
    newFrameIdx = min(lastMatched,max(1,round(newFrameIdx)));
    if newFrameIdx < 1 || newFrameIdx > data.video.numFrames
        stop(hd.timer); hd.play.Text = 'Play'; return;
    end
    % Index is acquisition-frame identity, independent of encoded video time.
    CData = read(data.video.vid, newFrameIdx);

    hd = shared.myPlot(@image, hd, 'image', hd.ax, CData);
    uistack(hd.image, "bottom")
    frameIdx = newFrameIdx;

    % update Time, Frame, and slider
    hd.frame.Value = frameIdx;
    hd.time.Value = data.video.t(frameIdx);
    hd.slider.Value = frameIdx;
    data.video.frameIdx = frameIdx;
    data.video.hd = hd;

    redrawMarkers();
end

% timeChanged listen function
function updateVideoTime(newTime)
    if ~data.has('video'); return; end  % no video
    
    frameRate = data.getFrameRate();
    requested = shared.time_to_frame(data.video.t,newTime);
    if requested > data.video.numFrames && strcmp(data.video.hd.timer.Running, 'on')
        stop(data.video.hd.timer); data.video.hd.play.Text = 'Play';
    end
    newFrameIdx = min(data.video.numFrames, max(1, requested));
    if newFrameIdx ~= data.video.frameIdx
        updateVideoFrame(newFrameIdx);
    end
end

function updateInfo()
    if ~data.has('video'); return; end
    hd = data.video.hd;
    data.video.numFrames = data.video.vid.NumFrames;
    data.video.t = data.getFrameTimes(data.video.numFrames);
    frameIdx = min(data.video.frameIdx, find(isfinite(data.video.t),1,'last'));
    % initialize Time, Frame, and slider
    hd.frame.Value = frameIdx;
    hd.time.Value = data.video.t(frameIdx);
    hd.slider.Value = frameIdx;

    frameRate = data.getFrameRate();
    hd.frameRate.Value = frameRate;

    % It's slow if opening video for the first time.
    totalFrames = data.video.vid.NumFrames;
    data.video.numFrames = totalFrames;
    data.video.t = data.getFrameTimes(totalFrames);
    lastMatched = find(isfinite(data.video.t),1,'last');

    hd.slider.Limits = [1 max(2,lastMatched)];
    % major ticks are minute marks, while values are still frame#
    tickTimes = data.video.t(1):60:data.video.t(lastMatched);
    hd.slider.MajorTicks = shared.time_to_frame(data.video.t,tickTimes);
    hd.slider.MajorTickLabels = string(round(tickTimes/60))+"'";
    
    hd.frame.Limits = [1 max(2,lastMatched)];
    
    hd.info.Text = sprintf('Size: %dx%dpx\nFrames: %d', ...
        data.video.vid.Height, data.video.vid.Width, totalFrames);

    data.video.hd = hd;
    updateTitle();
end

function updateFrameRate(value)
    if data.has('video')
        data.setFrameRate(value);
    end
end

% callback function for frame-by-frame buttons
function moveVideoFrame(direction)
    if ~data.has('video'), return; end
    playStep = bitshift(1, length(data.video.hd.next.Text)-1);
    if isempty(fig.CurrentModifier)
        % click without cotrol, move frame forward or backward
        last = find(isfinite(data.video.t),1,'last');
        newFrameIdx = min(last, max(1, data.video.frameIdx + direction * playStep));
        data.setTime(data.video.t(newFrameIdx));
    elseif ismember('control', fig.CurrentModifier)
        % control + click: adjust frame step size
        newStep = bitshift(playStep, direction); % *2 or /2
        if newStep >= 1 && newStep <= 16
            playStep = newStep; 
            textlen = length(dec2bin(playStep));
            data.video.hd.next.Text = repmat('>',1, textlen);
            data.video.hd.last.Text = repmat('<',1, textlen);
        end
    end
end

function sliderMoved(src,~)
    idx = min(find(isfinite(data.video.t),1,'last'),max(1,round(src.Value)));
    data.setTime(data.video.t(idx));
end

function manualFrameInput(~,~)
    hd = data.video.hd;
    frameIdx = min(find(isfinite(data.video.t),1,'last'),round(hd.frame.Value));
    frameRate = data.getFrameRate();
    hd.time.Value = data.video.t(frameIdx);
    data.setTime(hd.time.Value) % notify other modules.
end

function togglePlay(~,~)
    if ~data.has('video'), return; end
    hd = data.video.hd;
    if strcmp(hd.play.Text, 'Play')
        hd.play.Text = 'Pause';
        start(hd.timer);
    else
        hd.play.Text = 'Play';
        drawnow
        stop(hd.timer);
    end
end

function timerRunning(~,~)
    if ~data.has('video'), return; end
    playStep = bitshift(1, length(data.video.hd.next.Text)-1);
    last = find(isfinite(data.video.t),1,'last');
    % Advance from the displayed frame; rendering time never skips a step.
    newFrameIdx = min(last, data.video.frameIdx + playStep);
    data.setTime(data.video.t(newFrameIdx));
    if newFrameIdx >= last
        stop(data.video.hd.timer); data.video.hd.play.Text = 'Play';
    end
    drawnow
end

function onInfoChanged()
    if ~data.has('video'), return; end
    updateInfo();
    % the time base may have changed: show the frame at the current time
    updateVideoFrame(shared.time_to_frame(data.video.t, data.currentTime));
end

% === markers ==============================================================
% All markers on the video are drawn here, from a marker state. The live
% display builds the state from the current DLC and gait data; a video
% export takes one snapshot of it so later edits do not affect the file.

function redrawMarkers()
    if ~data.has('video'), return; end
    drawMarkers(markerState(), data.video.frameIdx);
end

% Collect what the markers need from the DLC and gait modules.
%   state.dlc   [] or struct: bodypart, x, y (per frame), tempX, tempY ([] if none)
%   state.steps [] or struct: t, x, y (per step), from GAIT.current_steps
function state = markerState()
    state = struct('dlc', [], 'steps', []);
    if data.has('dlc')
        tabledlc = data.dlc.table;
        bodypart = data.dlc.hd.list_bodyparts.Value;
        d.bodypart = bodypart;
        d.x = tabledlc.([bodypart '_x']);
        d.y = tabledlc.([bodypart '_y']);
        d.tempX = []; d.tempY = [];
        if ismember('temp_x', tabledlc.Properties.VariableNames) && ...
                isfield(data.dlc, 'seg_bodypart') && strcmp(data.dlc.seg_bodypart, bodypart)
            d.tempX = tabledlc.temp_x;
            d.tempY = tabledlc.temp_y;
        end
        state.dlc = d;
    end
    state.steps = GAIT.current_steps(data);
end

% Draw the markers of one frame. Step markers fade with distance in time
% from the frame: alpha = 2/(1+exp(|t_step - t_frame| / 1 s)).
function drawMarkers(state, frameIdx)
    hd = data.video.hd;

    % gait steps
    if ~isempty(state.steps) && ~isempty(state.steps.t)
        hd = shared.myPlot(@scatter, hd, 'stepMarker', hd.ax, ...
            state.steps.x, state.steps.y, ...
            'Marker', 'o', 'MarkerEdgeColor', 'm', 'LineWidth', 2, 'HitTest', 'off');
        frameT = data.video.t(frameIdx);
        set(hd.stepMarker, 'AlphaData', stepAlpha(state.steps.t, frameT), ...
            'MarkerEdgeAlpha', 'flat', 'Visible', 'on');
    else
        hd = hideMarker(hd, 'stepMarker');
    end

    % DLC: committed marker on top, fix preview below it
    d = state.dlc;
    if isempty(d) || frameIdx > numel(d.x)
        hd = hideMarker(hd, 'dlcMarker');
        hd = hideMarker(hd, 'dlcTempMarker');
    else
        if ~isempty(d.tempX)
            hd = shared.myPlot(@plot, hd, 'dlcTempMarker', hd.ax, ...
                d.tempX(frameIdx), d.tempY(frameIdx), 'go', 'LineWidth', 2, 'HitTest','off');
            hd.dlcTempMarker.Visible = 'on';
        else
            hd = hideMarker(hd, 'dlcTempMarker');
        end
        hd = shared.myPlot(@plot, hd, 'dlcMarker', hd.ax, ...
            d.x(frameIdx), d.y(frameIdx), 'c+', 'LineWidth', 2, 'HitTest','off');
        hd.dlcMarker.Visible = 'on';
        uistack(hd.dlcMarker, "top")
    end
    data.video.hd = hd;
end

function hd = hideMarker(hd, field)
    if isfield(hd, field) && isgraphics(hd.(field))
        hd.(field).Visible = 'off';
    end
end

function a = stepAlpha(stepT, frameT)
    a = 2 ./ (1 + exp(abs(stepT - frameT)));
end

% drag the markers ==========================
function onMouseDown(~, ~)
    if data.has('dlc') 
        hd = data.video.hd;
        % begin dragging
        cp = hd.ax.CurrentPoint;   % [x y] in axes data units
        cx = cp(1,1); cy = cp(1,2);
        xlims = hd.ax.XLim;
        ylims = hd.ax.YLim;
        tolx = 0.01 * diff(xlims);
        toly = 0.01 * diff(ylims);
        if (isfield(hd, 'dlcMarker') && ...
            hd.dlcMarker.Visible && ...
            abs(cx - hd.dlcMarker.XData) < tolx && ... 
            abs(cy - hd.dlcMarker.YData) < toly)
                drag.marker = hd.dlcMarker;
                drag.offsetX = cx - hd.dlcMarker.XData;
                drag.offsetY = cy - hd.dlcMarker.YData;
                data.video.drag = drag;
        end
        if (isfield(hd, 'dlcTempMarker') && ...
            hd.dlcTempMarker.Visible && ...
            abs(cx - hd.dlcTempMarker.XData) < tolx && ... 
            abs(cy - hd.dlcTempMarker.YData) < toly)
                drag.marker = hd.dlcTempMarker;
                drag.offsetX = cx - hd.dlcTempMarker.XData;
                drag.offsetY = cy - hd.dlcTempMarker.YData;
                data.video.drag = drag;
        end
    end
end

function onMouseUp(~, ~)
    hd = data.video.hd;
    % update xy data and finish dragging
    if isfield(data.video, 'drag')
        drag = data.video.drag;
        frameIdx = data.video.frameIdx;

        if isequal(drag.marker, hd.dlcMarker)
            bodypart = data.dlc.hd.list_bodyparts.Value;
            data.dlc.table.([bodypart '_x'])(frameIdx) = drag.marker.XData;
            data.dlc.table.([bodypart '_y'])(frameIdx) = drag.marker.YData;
            data.dlc.previewParameters = []; % source changed; regenerate before Save As
            data.notifyDLC('edit', {bodypart});
        elseif isequal(drag.marker, hd.dlcTempMarker)
            data.dlc.table.temp_x(frameIdx) = drag.marker.XData;
            data.dlc.table.temp_y(frameIdx) = drag.marker.YData;
            data.notifyDLC('preview');
        end
        data.video = rmfield(data.video, 'drag');
    end
end

function onMouseMove(~, ~)
    hd = data.video.hd;
    cp = hd.ax.CurrentPoint;
    cx = cp(1,1);  cy = cp(1,2);
    xlims = hd.ax.XLim;
    ylims = hd.ax.YLim;
    tolx = 0.01 * diff(xlims);
    toly = 0.01 * diff(ylims);
    
    if ~isfield(data.video, 'drag')
        % not dragging, only change curser
        if data.has('dlc') 
            if (isfield(hd, 'dlcMarker') && ...
                hd.dlcMarker.Visible && ...
                abs(cx - hd.dlcMarker.XData) < tolx && ... 
                abs(cy - hd.dlcMarker.YData) < toly) ...
                || ...
               (isfield(hd, 'dlcTempMarker') && ...
                hd.dlcTempMarker.Visible && ...
                abs(cx - hd.dlcTempMarker.XData) < tolx && ... 
                abs(cy - hd.dlcTempMarker.YData) < toly)
                    fig.Pointer = 'hand';
            else
                    fig.Pointer = 'arrow';
            end
        end
    else
        % dragging
        drag = data.video.drag;
        drag.marker.XData = cx - drag.offsetX;
        drag.marker.YData = cy - drag.offsetY;
    end
end

function onClose(~,~)
    if ~shared.confirm_close(fig, 'Video Viewer'), return; end
    hd=data.video.hd;
    % Stop timer
    if isfield(hd, 'timer') && isvalid(hd.timer)
        stop(hd.timer);
    end

    % Clear all the handles, listeners, timer;
    field = fields(hd);
    for k=1:length(field)
        try
            delete(hd.(field{k}))
        catch ME
            disp(field{k})
            disp(hd.(field{k}))
            warning(ME.identifier, '%s', ME.message);
        end
    end

    % Clear data and graphic handles
    data.video = struct();
    % Clear saved figure handle
    data.fig = rmfield(data.fig, 'video');
    delete(fig);  % finally close the GUI
    data.moduleClosed();
end
end