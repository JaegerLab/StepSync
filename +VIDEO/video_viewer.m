function fig = video_viewer(default_path)
% App state

data = shared.SessionData.instance();

drawGUI(default_path);


function drawGUI(default_path)
    % Main UI figure with grid layout
    fig = uifigure('Name', 'Video Viewer', 'Position', [100 100 600 600], ...
        'CloseRequestFcn', @onClose);
    % for dragging markers
    fig.WindowButtonDownFcn   = @(src,evt)onMouseDown(src, evt);
    fig.WindowButtonMotionFcn = @(src,evt)onMouseMove(src, evt);
    fig.WindowButtonUpFcn     = @(src,evt)onMouseUp(src, evt);
    drawnow

    gl = uigridlayout(fig, [4, 2]);
    gl.RowHeight = {30, 30, 40, '1x'};
    gl.ColumnWidth = {'1x', 100};
    gl.Padding = [10 10 10 10];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 8;

    % Row 1: video path and open button
    hPath = uieditfield(gl, 'text', 'Editable', 'off');
    if nargin>=1
        hPath.Value = default_path;
    end
    hPath.Layout.Row = 1; hPath.Layout.Column = 1;

    uibutton(gl, 'Text', 'Open Video', 'ButtonPushedFcn', @openVideo, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));

    hd = struct();

    % Row 2: frame info
    subgrid1 = uigridlayout(gl, [1 3], 'Padding', [0 0 0 0]);
    subgrid1.ColumnWidth = {'1x', 130, 100, 90};
    subgrid1.Layout.Row = 2; subgrid1.Layout.Column = 1;

        % subgrid1
        hd.info = uilabel(subgrid1, ...
            'Text', 'Info:', 'BackgroundColor','W');

        hd.frameRate = uieditfield(subgrid1, 'numeric', ...
            'Limits', [0 Inf], ...
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
    subgrid2.Layout.Row = 2; subgrid2.Layout.Column = 2;

        hd.last = uibutton(subgrid2, 'Text', '<', ...
            'Tooltip','Ctrl+Click to change step size', ...
            'ButtonPushedFcn', @(src,evt)moveVideoFrame(-1));
        hd.next = uibutton(subgrid2, 'Text', '>', ...
            'Tooltip','Ctrl+Click to change step size', ...
            'ButtonPushedFcn', @(src,evt)moveVideoFrame(1));
    
    % Row 3: slider and play button
    hd.slider = uislider(gl, 'ValueChangedFcn', @sliderMoved);
    hd.play = uibutton(gl, 'Text', 'Play', 'ButtonPushedFcn', @togglePlay);

    % Row 4: axes for video
    ax = uiaxes(gl);
    ax.Layout.Row = 4; ax.Layout.Column = [1 2];
    ax.XTick = []; ax.YTick = [];

    % Timer for playback
    hd.timer = timer('ExecutionMode', 'fixedRate', ...
        'Period', 0.001, ...
        'TimerFcn', @timerRunning);

    hd.path = hPath;
    hd.ax = ax;
    axis(hd.ax, 'image'); axis(hd.ax, 'off');
    hold(hd.ax, "on");

    % add listeners
    hd.timeListener = addlistener(data, 'TimeChanged', @(src, ~)updateVideoTime(src.currentTime));
    hd.infoListener = addlistener(data, 'InfoChanged', @(~,~)updateInfo());
    hd.dataListener = addlistener(data, 'DataChanged', @(src, ~)updateVideoFrame(src.video.frameIdx));

    data.video(1).hd = hd;
end

function openVideo(~,~)
    hd = data.video.hd;
    filename = hd.path.Value;
    if exist(filename, "file") ~= 2
        if isempty(filename)
            filename='*.mp4';
        else
            [pathname, file, ext] = fileparts(filename);
            if isempty(ext)
                % it's a path
                filename = fullfile(pathname, file, '*.mp4');
            else
                % it's a filename
                filename = fullfile(pathname, ['*' ext]);
            end
        end
        [file, path] = uigetfile(filename, 'Open Video file');
        if isequal(file, 0); return; end
        filename = fullfile(path, file);
        hd.path.Value = filename;
    end
    data.video.vid = VideoReader(filename);
    data.video.hd = hd;

    data.video.frameRate = data.getFrameRate();
    hd.frameRate.Value = data.video.frameRate;

    % initialize video image
    updateVideoFrame()

    data.video.frameIdx = 1;
    updateInfo
end

%% main == event response callback function
function updateVideoFrame(newFrameIdx)
    % no argument = display next frame
    hd = data.video.hd;
    frameRate = data.getFrameRate();
    if ~data.has('video') || ... % no video
       (nargin ==0 && ~data.video.vid.hasFrame()) || ... % no next frame
       (nargin ==1 && (newFrameIdx < 1 || newFrameIdx > data.video.numFrames)) % out of bound
        stop(hd.timer);
        hd.play.Text = 'Play';
        return; 
    end
    
    % read video frame
    if nargin == 0
        % no argument, display next frame
        CData = readFrame(data.video.vid); % faster way to read next frame
        newFrameIdx = round(data.video.vid.CurrentTime * frameRate);
    else
        CData = read(data.video.vid, newFrameIdx);
    end
    
    hd = shared.myPlot(@image, hd, 'image', hd.ax, CData);
    uistack(hd.image, "bottom")
    frameIdx = newFrameIdx;

    % update Time, Frame, and slider
    hd.frame.Value = frameIdx;
    hd.time.Value = frameIdx / frameRate;
    hd.slider.Value = frameIdx;
    data.video.frameIdx = frameIdx;
    data.video.hd = hd;

    drawDLCMarker
    drawGaitMarker
end

% timeChanged listen function
function updateVideoTime(newTime)
    if ~data.has('video'); return; end  % no video
    
    frameRate = data.getFrameRate();
    newFrameIdx = round(newTime * frameRate);
    if newFrameIdx == data.video.frameIdx + 1
        updateVideoFrame()
    elseif newFrameIdx ~= data.video.frameIdx
        updateVideoFrame(newFrameIdx);
    end
end

function updateInfo()
    if ~data.has('video'); return; end
    hd = data.video.hd;
    frameIdx = data.video.frameIdx;
    % initialize Time, Frame, and slider
    hd.frame.Value = frameIdx;
    hd.time.Value = data.video.vid.CurrentTime;
    data.currentTime = data.video.vid.CurrentTime;
    hd.slider.Value = frameIdx;

    frameRate = data.getFrameRate();
    hd.frameRate.Value = frameRate;

    % It's slow if opening video for the first time.
    totalFrames = data.video.vid.NumFrames;
    data.video.numFrames = totalFrames;

    hd.slider.Limits = [1 totalFrames];
    % major ticks are minute marks, while values are still frame#
    hd.slider.MajorTicks = 1:frameRate*60:totalFrames;
    hd.slider.MajorTickLabels = (0:totalFrames/frameRate/60)+"'";
    
    hd.frame.Limits = [1 totalFrames];
    
    hd.info.Text = sprintf('Size: %dx%dpx\nFrames: %d', ...
        data.video.vid.Height, data.video.vid.Width, totalFrames);

    data.video.hd = hd;
end

function updateFrameRate(value)
    data.frameRate = value;
    notify(data, 'InfoChanged');
end

% callback function for frame-by-frame buttons
function moveVideoFrame(direction)
    playStep = bitshift(1, length(data.video.hd.next.Text)-1);
    if isempty(fig.CurrentModifier)
        % click without cotrol, move frame forward or backward
        newFrameIdx = data.video.frameIdx + direction * playStep;
        data.setTime(newFrameIdx/data.getFrameRate());
    elseif ismember('control', fig.CurrentModifier)
        % control + click: adjust step size or play speed
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
    data.setTime(src.Value/data.getFrameRate());
end

function manualFrameInput(~,~)
    hd = data.video.hd;
    frameIdx = round(hd.frame.Value);
    frameRate = data.getFrameRate();
    hd.time.Value = frameIdx / frameRate;
    data.setTime(hd.time.Value) % notify other modules.
end

function togglePlay(~,~)
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
    playStep = bitshift(1, length(data.video.hd.next.Text)-1);
    newFrameIdx = data.video.frameIdx + playStep;
    data.setTime(newFrameIdx/data.getFrameRate());
    drawnow
end

% if there's DLC, draw the marker on the video
function drawDLCMarker()
    if data.has('dlc')
        hd = data.video.hd;
        frameIdx = data.video.frameIdx;
        tabledlc = data.dlc.table;
        bodypart = data.dlc.hd.list_bodyparts.Value;

        % show temp marker
        if ismember('temp_x', tabledlc.Properties.VariableNames)
            hd = shared.myPlot( ...
                @plot, hd, 'dlcTempMarker', hd.ax, ...
                tabledlc.temp_x(frameIdx), tabledlc.temp_y(frameIdx), ...
                'r+', 'LineWidth', 2, 'HitTest','off');
        end

        % show marker
        hd = shared.myPlot(@plot, hd, 'dlcMarker', hd.ax, ...
                tabledlc.([bodypart '_x'])(frameIdx), tabledlc.([bodypart '_y'])(frameIdx), ...
                'g+', 'LineWidth', 2, 'HitTest','off');
        uistack(hd.dlcMarker, "top")
        data.video.hd = hd;
    end
end

% if there's gait, draw gait landmarks on the video
function drawGaitMarker()
    % gait marker is implemented in the GAIT.gait_viewer module
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
        elseif isequal(drag.marker, hd.dlcTempMarker)
            data.dlc.table.temp_x(frameIdx) = drag.marker.XData;
            data.dlc.table.temp_y(frameIdx) = drag.marker.YData;
        end
        notify(data,'DataChanged');
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
end
end