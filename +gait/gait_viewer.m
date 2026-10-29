function fig = gait_viewer()

    data = shared.SessionData.instance();
    % true while the "pose changed" prompt is open; further PoseChanged
    % events are ignored until the user answers it.
    posePromptPending = false;
    drawGUI()

    function drawGUI()
        hd = struct;
        % gait viewer window with uigridlayout
        fig = uifigure('Name', 'StepSync Gait', 'Position', shared.window_position('gait', [100 100 1000 500]), ...
            'CloseRequestFcn',@onClose);
        data.fig(1).gait = fig;
        shared.MenuBar(fig, {'Open', @openGait; 'Import Pose', @importPaws; 'Save', @saveGait});
        drawnow
        grid1 = uigridlayout(fig, Padding = [20,20,20,20], ...
            ColumnWidth = {'1x', 140}, RowHeight = {30, '1x', 30});

        %% Row 1: pose processing
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0], ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 1));
        subgrid1.ColumnWidth = {'1x', 150,130,130,120,120};
        hd.info = uilabel(subgrid1,'Text',' Info:', 'BackgroundColor','w');
        hd.frameRate = shared.frame_rate_field(subgrid1);
        hd.resolution = uieditfield(subgrid1,'numeric','Value',30, ...
            'ValueDisplayFormat','Resolution: %d px/cm', ...
            'ValueChangedFcn', @(~,~)updateInfo);
        hd.pawthresh = uieditfield(subgrid1,'numeric','Value',10, ...
            'ValueDisplayFormat','Paw thresh: %.2f cm', ...
            'ValueChangedFcn', @pawThreshChanged);
        hd.minTimeInterval = uieditfield(subgrid1,'numeric','Value',0.2, ...
            'ValueDisplayFormat','Min interval: %.2f s', ...
            'Limits', [0 Inf], 'LowerLimitInclusive', 'off', ...
            'ValueChangedFcn', @intervalChanged);
        
        uibutton(subgrid1, 'Text', 'Edit Mask', 'ButtonPushedFcn', @openMask);
        % shares the Min interval cell; shown instead of it for onset/offset
        hd.nearZero = uieditfield(subgrid1,'numeric','AllowEmpty','on','Value',[], ...
            'ValueDisplayFormat','Near-zero: %.2f cm/s', ...
            'Limits', [0 Inf], 'Visible', 'off', ...
            'ValueChangedFcn', @nearZeroChanged);
        hd.nearZero.Layout = hd.minTimeInterval.Layout;

        hd.trace = uidropdown(grid1, 'Items',{'X', 'Y', 'Speed'}, 'Value', 'X', ...
            'ValueChangedFcn', @traceChanged, ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));


        %% Row 2: pose plot
        hd.ax = createAxes(grid1);
        ylabel(hd.ax, 'X (cm)');

        subgrid3 = uigridlayout(grid1, [4 1], Padding = [0 0 0 0], ...
            RowHeight={'1x', 30, '1x', 30});
        subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
        hd.pawList = uilistbox(subgrid3, 'Multiselect', 'off', ...
            'ValueChangedFcn', @pawChanged, 'Enable','off');
        subgrid4 = uigridlayout(subgrid3, [1 2], Padding = [0 0 0 0]);
            hd.stepCheck = uicheckbox(subgrid4, Text='Steps', Value=1, ...
                Enable='off', ValueChangedFcn = @stepCheckChanged);
            hd.stepNum = uieditfield(subgrid4, 'numeric', Value = 0, Editable='off', ...
                ValueDisplayFormat = 'n = %d');
        hd.stepList = uilistbox(subgrid3, 'Multiselect', 'off', ...
            'ValueChangedFcn', @stepChanged, 'Enable','off');
        hd.sta = uibutton(subgrid3, Text='Step Triggered Avg', Enable='off', ...
                ButtonPushedFcn=@openSTA);

        %% Row 3: zoom in, zoom out, update buttons
        subgrid2 = uigridlayout(grid1, [1 4], 'Padding', [0 0 0 0]);
        subgrid2.Layout.Row = 3; subgrid2.Layout.Column = 2;
        uibutton(subgrid2,'Text','🔍︎+','ButtonPushedFcn',@zoomIn, ...
            'Tooltip','Zoom in');
        uibutton(subgrid2,'Text','🔍︎-','ButtonPushedFcn',@zoomOut, ...
            'Tooltip','Zoom out');
        uibutton(subgrid2,'Text','⭯','ButtonPushedFcn',@refresh, ...
            'Tooltip','Refresh');
        uibutton(subgrid2,'Text','[➜','ButtonPushedFcn',@exportAxes, ...
            'Tooltip','Pop out');

        % add listeners
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateGaitTime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateGaitZoom(src.currentZoom));
        hd.infoListener = addlistener(data, 'InfoChanged', @(~,~)updateInfo());
        hd.maskListener = addlistener(data, 'MaskChanged', @(~,~)updateInfo());
        hd.previewListener = addlistener(data, 'MaskPreviewChanged', @(~,~)previewChanged());
        hd.poseListener = addlistener(data, 'PoseChanged', @(~,evt)onPoseChanged(evt));

        data.gait(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    % plot axes in rows 2-3, column 1 of the main grid
    function ax = createAxes(parent)
        ax = uiaxes(parent); hold(ax, 'on');
        ax.ButtonDownFcn = @axClicked;
        ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        ax.Layout.Row = [2 3]; ax.Layout.Column = 1;
        xlabel(ax, 'Time (s)')
        disableDefaultInteractivity(ax)
    end

    % A right y axis cannot be removed from an axes: replace the axes. The
    % plots are recreated by the next plotTrace/plotSteps.
    function hd = removeRightAxis(hd)
        old = hd.ax;
        hd.ax = createAxes(old.Parent);
        ylabel(hd.ax, old.YAxis(1).Label.String);
        xlim(hd.ax, old.XLim);
        delete(old);
        hd = rmfield(hd, intersect(fieldnames(hd), ...
            {'maskSpeedGood', 'maskSpeedBad', 'maskSpeedThres'}));
    end

    function importPaws(~,~)
        hd = data.gait.hd;
        if ~data.has('pose')
            % no pose data, read pose from file.
            [filename, pathname]=uigetfile(fullfile(data.defaultPath, '*.csv'), 'Open DeepLabCut file');
            if isequal(pathname,0), return; end
            filename=fullfile(pathname, filename);
            if ~exist(filename, "file"), return; end
            data.rememberPath(filename);

            tablePose = pose.align_to_video(pose.read_pose(filename), fig);
            partList = tablePose.Properties.UserData;
            poseFile = filename;
            source = filename;
        else
            % read pose from pose_viewer
            tablePose = data.pose.table;
            partList = data.pose.hd.bodypart.Items;
            poseFile = '';
            if isfield(data.pose, 'filename'), poseFile = data.pose.filename; end
            source = 'pose_module';  % follow later pose edits (see onPoseChanged)
        end
        
        % select paws
        [pawIdx, tf] = listdlg('PromptString','Select paws:','ListString',partList);
        drawnow; figure(fig);
        if ~tf, return; end

        % add selected body parts into GUI lists
        hd.pawList.Items = partList(pawIdx); hd.pawList.Enable = 'on';
        hd.pawList.ItemsData = 1:numel(pawIdx);

        % save raw x, y in pixels, 
        % so that later no need to read from pose when frame rate changes.
        for field = {'maskFig','sta_GUI'}
            if isfield(hd, field{1}) && isgraphics(hd.(field{1})), close(hd.(field{1})); end
        end
        invalidateSteps();
        oldHd = data.gait.hd;
        data.gait = struct('hd', oldHd);
        data.gait.source = source;
        data.gait.filename = poseFile;   % shown in the title
        posePromptPending = false;
        for ii = 1:numel(hd.pawList.Items) 
            pawName = hd.pawList.Items{ii};
            data.gait.paw(ii).name = pawName;
            data.gait.paw(ii).rawX = tablePose.([pawName '_x']);
            data.gait.paw(ii).rawY = tablePose.([pawName '_y']);
            data.gait.paw(ii).thresh = struct('x',NaN,'y',NaN,'speed',NaN,'nearZero',NaN);
        end

        % enable Steps
        hd.stepCheck.Enable = 'on';
        hd.sta.Enable = 'on';
        hd.stepList.Enable = 'on';
        hd.stepList.Items = {'rising','falling','onset','offset','peak','valley'};
        hd.stepList.ItemsData = {'rising','falling','onset','offset','peak','valley'};
        hd.stepList.Value = 'rising';

        getSpeeds();
        plotTrace();
        getSteps();
        plotSteps();
        updateTitle();
    end

    % The title shows the gait file last opened or saved, otherwise the pose
    % file the paws were imported from.
    function updateTitle()
        fig.Name = 'StepSync Gait';
        if ~data.has('gait'), return; end
        shown = '';
        if isfield(data.gait, 'filename'), shown = data.gait.filename; end
        if isfield(data.gait, 'displayName'), shown = data.gait.displayName; end
        if ~isempty(shown), fig.Name = ['StepSync Gait: ' shown]; end
    end

    %% === Save and Open gait files (gait.save_gait / gait.read_gait) ===
    function saveGait(~,~)
        if ~data.has('gait')
            uialert(fig, 'There is no gait data to save.', 'Save');
            return;
        end
        [range, ok] = shared.ask_save_range(fig, 'Gait');
        if ~ok, return; end
        if ~isfield(data.gait, 'filename'), data.gait.filename = ''; end
        base = 'gait';
        if ~isempty(data.gait.filename), [~, base] = fileparts(data.gait.filename); end
        [file, path] = uiputfile('*.mat', 'Save gait', fullfile(data.defaultPath, [base '_gait.mat']));
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        % never overwrite the pose input or the gait file opened
        originals = {data.gait.filename};
        if isfield(data.gait, 'sourceFile'), originals{end+1} = data.gait.sourceFile; end
        if any(strcmpi(filename, originals))
            uialert(fig, sprintf('%s is a file this gait data was read from. Choose another name.', file), ...
                'Save refused');
            return;
        end
        hd = data.gait.hd;
        syncSelection();
        settings = struct('resolution', hd.resolution.Value, 'minInterval', hd.minTimeInterval.Value);
        gait.save_gait(filename, data.gait, settings, data.getFrameRate(), range);
        data.rememberPath(filename);
        data.gait.displayName = filename;
        updateTitle();
    end

    % Replace the gait data with a saved file and recalculate.
    function openGait(~,~)
        [file, path] = uigetfile(fullfile(data.defaultPath, '*.mat'), 'Open gait file');
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        try
            g = gait.read_gait(filename);
        catch ME
            uialert(fig, ME.message, 'Open gait file');
            return;
        end
        data.rememberPath(filename);

        hd = data.gait.hd;
        for field = {'maskFig','sta_GUI'}
            if isfield(hd, field{1}) && isgraphics(hd.(field{1})), close(hd.(field{1})); end
        end
        invalidateSteps();
        % Follow pose edits again only if the Pose viewer has the same file open.
        source = g.source;
        if strcmp(source, 'pose_module')
            poseFiles = {};
            if data.has('pose') && isfield(data.pose, 'filename'), poseFiles{end+1} = data.pose.filename; end
            if data.has('pose') && isfield(data.pose, 'sourceFile'), poseFiles{end+1} = data.pose.sourceFile; end
            if isempty(g.filename) || ~any(strcmpi(g.filename, poseFiles)), source = filename; end
        end
        data.gait = struct('hd', hd);
        data.gait.source = source;
        data.gait.filename = g.filename;
        data.gait.displayName = filename;
        data.gait.sourceFile = filename;
        data.gait.mask = g.mask;
        if ~isempty(g.maskParam), data.gait.maskParam = g.maskParam; end
        if isfield(g, 'sta') && ~isempty(g.sta), data.gait.sta = g.sta; end
        posePromptPending = false;
        data.gait.paw = g.paw;

        % widgets
        traces = struct('x', 'X', 'y', 'Y', 'speed', 'Speed');
        hd.pawList.Items = {g.paw.name};
        hd.pawList.ItemsData = 1:numel(g.paw);
        hd.pawList.Value = g.selection.paw;
        hd.pawList.Enable = 'on';
        hd.trace.Value = traces.(g.selection.trace);
        hd.resolution.Value = g.resolution;
        hd.minTimeInterval.Value = g.minInterval;
        hd.stepList.Items = {'rising','falling','onset','offset','peak','valley'};
        hd.stepList.ItemsData = hd.stepList.Items;
        hd.stepList.Value = g.selection.step;
        hd.stepList.Enable = 'on';
        hd.stepCheck.Value = g.selection.show;
        hd.stepCheck.Enable = 'on';
        hd.sta.Enable = 'on';

        getSpeeds();
        plotTrace();
        getSteps();
        plotSteps();
        updateTitle();

        rate = data.getFrameRate();
        if abs(rate - g.frameRate) > 1e-6 * max(1, g.frameRate)
            uialert(fig, sprintf(['The gait data was saved at %.4g Hz; the current frame rate is ' ...
                '%.4g Hz. Speeds and step times use the current rate.'], g.frameRate, rate), ...
                'Frame rate differs', 'Icon', 'warning');
        end
    end

    function getSpeeds()
        hd = data.gait.hd;
        data.gait.speedFactor = data.getFrameRate() / hd.resolution.Value;

        for ii = 1:numel(hd.pawList.Items)    
            paw = data.gait.paw(ii);

            % convert raw xy (in pixels) to xy (in centimeters)
            data.gait.paw(ii).x = paw.rawX./hd.resolution.Value;
            data.gait.paw(ii).y = paw.rawY./hd.resolution.Value;
            
            % calculate speed in cm/s
            data.gait.paw(ii).speed = ...
                gait.smooth_speed(paw.rawX, paw.rawY, 3) .* ...
                data.gait.speedFactor;

        end
        % reconstruct t
        data.gait.t = data.getFrameTimes(numel(data.gait.paw(1).rawX));
    end
   
    function plotTrace()
        hd = data.gait.hd;
        % preview gone: drop the right axis with its speed plots
        if ~hasSpeedPreview(data.gait.t) && numel(hd.ax.YAxis) > 1
            hd = removeRightAxis(hd);
        end
        hold(hd.ax, 'on');

        % get trace
        pawIdx = hd.pawList.Value;
        t = data.gait.t;
        traceType = lower(hd.trace.Value);
        trace = data.gait.paw(pawIdx).(traceType);

        % get mask
        if isfield(data.gait, 'maskTemp')
            mask = data.gait.maskTemp;
        elseif isfield(data.gait, 'mask')
            mask = data.gait.mask;
        else
            data.gait.mask = true(size(trace));
            mask = data.gait.mask;
        end
        if numel(mask) ~= numel(trace)
            error('gait:maskSize', 'Mask and trace sizes differ.');
        end
        mask = logical(mask(:));
        unmask = ~mask;

        % Always replace both traces, including empty selections.
        unmask = unmask | unmask([1 1:end-1]) | unmask([2:end end]);
        traceUnmask = trace; traceUnmask(~unmask) = NaN;
        traceMask = trace; traceMask(~mask) = NaN;
        hd = shared.myPlot(@plot, hd, 'pawUnmask', hd.ax, t, traceUnmask, ...
            'Color', '#AAAACC', 'HitTest', 'off');
        hd = shared.myPlot(@plot, hd, 'pawMask', hd.ax, t, traceMask, ...
            'Color', '#0000CC', 'HitTest', 'off');

        % plot threshold line
        % Preview colors may change; thresholds and events use committed data.
        thresh = selectedThreshold(trace, pawIdx, traceType);
        hd.pawthresh.Value = thresh; % restore threhold display.
        hd = shared.myPlot(@yline, hd, 'pawThresLine', hd.ax, ...
                        [], thresh, ...
                        'b:', 'HitTest', 'off');

        % time line
        hd = shared.myPlot(@xline, hd, 'timeline', hd.ax, ...
                        data.currentTime, [], ...
                        'k-', 'HitTest', 'off');

        % speed-threshold part of a mask preview, on the right y axis:
        % speed black where good, gray where bad, and the threshold
        if hasSpeedPreview(t)
            sp = data.gait.maskTempSpeed;
            good = logical(sp.good(:));
            bad = ~good;
            bad = bad | bad([1 1:end-1]) | bad([2:end end]);
            speedGood = sp.speed(:); speedGood(~good) = NaN;
            speedBad = sp.speed(:); speedBad(~bad) = NaN;
            yyaxis(hd.ax, 'right'); hold(hd.ax, 'on');
            hd = shared.myPlot(@plot, hd, 'maskSpeedBad', hd.ax, sp.t, speedBad, ...
                'Color', [0.6 0.6 0.6], 'LineStyle', '-', 'Marker', 'none', 'HitTest', 'off');
            hd = shared.myPlot(@plot, hd, 'maskSpeedGood', hd.ax, sp.t, speedGood, ...
                'Color', 'k', 'LineStyle', '-', 'Marker', 'none', 'HitTest', 'off');
            hd = shared.myPlot(@yline, hd, 'maskSpeedThres', hd.ax, ...
                [], sp.threshold, 'k--', 'HitTest', 'off');
            ylabel(hd.ax, 'Mask speed (cm/s)');
            hd.ax.YAxis(2).Color = 'k';
            yyaxis(hd.ax, 'left');
            hd.ax.YAxis(1).Color = [0.15 0.15 0.15];   % yyaxis recolours the left axis
        end

        data.gait.hd = hd;
    end

    function tf = hasSpeedPreview(t)
        tf = isfield(data.gait, 'maskTempSpeed') && ...
            numel(data.gait.maskTempSpeed.speed) == numel(t);
    end

    function invalidateSteps()
        wasValid = isfield(data.gait, 'stepsValid') && data.gait.stepsValid;
        data.gait.stepsValid = false;
        hd = data.gait.hd;
        if isfield(hd, 'stepGait') && isgraphics(hd.stepGait)
            hd.stepGait.Visible = 'off';
        end
        hd.stepNum.Value = 0;
        % Other viewers hide their step markers. A successful recalculation
        % publishes again from plotSteps().
        if wasValid, notify(data, 'GaitChanged'); end
    end

    % Copy the live gait selection into data.gait.selection, so that other
    % viewers (via gait.current_steps) never read gait's UI controls.
    function syncSelection()
        hd = data.gait.hd;
        sel.paw = hd.pawList.Value;
        sel.trace = lower(hd.trace.Value);
        sel.step = hd.stepList.Value;
        sel.show = logical(hd.stepCheck.Value) && isequal(hd.stepCheck.Enable, 'on');
        data.gait.selection = sel;
    end

    function thresh = selectedThreshold(trace, pawIdx, traceType)
        thresh = data.gait.paw(pawIdx).thresh.(traceType);
        if isnan(thresh)
            % Same automatic threshold in plot and calculation; independent of preview.
            thresh = mean(trace, 'omitnan');
            if ~isfinite(thresh), thresh = 0; end
        end
    end

    function getSteps()
        invalidateSteps();
        syncSelection();
        hd = data.gait.hd;
        pawIdx = hd.pawList.Value;
        traceType = lower(hd.trace.Value);
        trace = data.gait.paw(pawIdx).(traceType);
        threshold = selectedThreshold(trace, pawIdx, traceType);
        updateStepOptions(traceType);
        nearZero = NaN;
        if strcmp(traceType,'speed')
            nearZero = manualNearZero(pawIdx);
            if isfinite(nearZero)
                status = 'Set by hand. Clear the field to estimate it automatically.';
            else
                [nearZero, restInfo] = gait.auto_rest_threshold(trace, data.getFrameRate());
                status = ['Automatic: ' restInfo.status '. Type a value to override.'];
            end
            data.gait.paw(pawIdx).nearZeroStatus = status;
        end
        data.gait.paw(pawIdx).nearZeroThreshold = nearZero;
        interval = max(1, round(hd.minTimeInterval.Value * data.getFrameRate()));
        detectionMask = data.gait.mask & isfinite(data.gait.t);
        steps = gait.detect_steps(trace, detectionMask, threshold, interval, nearZero);
        % Commit only after every event type has been calculated successfully.
        fields = fieldnames(steps);
        for k = 1:numel(fields)
            data.gait.paw(pawIdx).(fields{k}) = steps.(fields{k});
        end
        data.gait.paw(pawIdx).traceType = traceType;
        data.gait.stepsPaw = pawIdx;
        data.gait.stepsTrace = traceType;
        data.gait.stepsValid = true;
        updateIntervalField();
    end

    % NaN: estimate automatically
    function value = manualNearZero(pawIdx)
        value = NaN;
        thresh = data.gait.paw(pawIdx).thresh;
        if isfield(thresh, 'nearZero') && ~isempty(thresh.nearZero), value = thresh.nearZero; end
    end

    % One cell for the parameter of the selected event: Near-zero for
    % onset/offset, Min interval for peak/valley, unused for rising/falling.
    function updateIntervalField()
        hd = data.gait.hd;
        step = hd.stepList.Value;
        isRest = ischar(step) && ismember(step, {'onset','offset'});
        hd.nearZero.Visible = isRest;
        hd.minTimeInterval.Visible = ~isRest;
        hd.minTimeInterval.Enable = ~(ischar(step) && ismember(step, {'rising','falling'}));
        if ~isRest || ~data.has('gait'), return; end
        pawIdx = hd.pawList.Value;
        if ~isfield(data.gait.paw, 'nearZeroThreshold'), return; end
        value = data.gait.paw(pawIdx).nearZeroThreshold;
        if isfinite(value), hd.nearZero.Value = value; else, hd.nearZero.Value = []; end
        hd.nearZero.FontAngle = 'normal';
        if ~isfinite(manualNearZero(pawIdx)), hd.nearZero.FontAngle = 'italic'; end
        if isfield(data.gait.paw, 'nearZeroStatus') && ~isempty(data.gait.paw(pawIdx).nearZeroStatus)
            hd.nearZero.Tooltip = data.gait.paw(pawIdx).nearZeroStatus;
        end
    end

    function nearZeroChanged(src,~)
        if ~data.has('gait'), return; end
        invalidateSteps();
        value = src.Value;
        if isempty(value), value = NaN; end
        data.gait.paw(data.gait.hd.pawList.Value).thresh.nearZero = value;
        getSteps(); plotSteps();
    end

    function previewChanged()
        if ~data.has('gait'), return; end
        oldAx = data.gait.hd.ax;
        plotTrace();
        % the axes were replaced: redraw the step markers on the new ones
        if data.gait.hd.ax ~= oldAx, plotSteps(); end
    end

    function updateStepOptions(traceType)
        hd = data.gait.hd;
        selected = hd.stepList.Value;
        items = {'rising','falling','peak','valley'};
        if strcmp(traceType,'speed')
            items = {'rising','falling','onset','offset','peak','valley'};
            hd.pawthresh.ValueDisplayFormat = 'Paw thresh: %.2f cm/s';
            ylabel(hd.ax,'Speed (cm/s)');
        else
            hd.pawthresh.ValueDisplayFormat = 'Paw thresh: %.2f cm';
            ylabel(hd.ax,[upper(traceType) ' (cm)']);
        end
        hd.stepList.ItemsData = {};
        hd.stepList.Items = items;
        hd.stepList.ItemsData = items;
        if ismember(selected,items), hd.stepList.Value = selected; else, hd.stepList.Value = 'rising'; end
    end

    % Draw gait's own step markers, then tell the other viewers to redraw
    % theirs from gait.current_steps(data).
    function plotSteps()
        syncSelection();
        hd = data.gait.hd;
        if gait.steps_current(data) && data.gait.selection.show
            pawIdx = data.gait.selection.paw;
            stepIdx = data.gait.paw(pawIdx).(data.gait.selection.step);
            stepT = data.gait.t(stepIdx);

            % numbers of gait step points.
            hd.stepNum.Value = length(stepIdx);

            selectedTrace = data.gait.paw(pawIdx).(data.gait.selection.trace);
            hd = shared.myPlot(@scatter, hd, 'stepGait', hd.ax, ...
                            stepT, selectedTrace(stepIdx), ...
                            'Marker', 'o', 'MarkerEdgeColor', 'm', 'LineWidth', 2, ...
                            'HitTest', 'off');
            hd.stepGait.Visible = 'on';
        elseif isfield(hd, 'stepGait') && isgraphics(hd.stepGait)
            hd.stepGait.Visible = 'off';
        end
        data.gait.hd = hd;
        notify(data, 'GaitChanged');
    end

    function openMask(~,~)
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.gait.hd;
        if ~isfield(hd, 'maskFig') || ~isgraphics(hd.maskFig, 'figure')
            % open a new window
            data.gait.hd.maskFig = gait.mask_GUI(mousePos);
            notify(data, 'WindowsChanged');
        else
            % if window is already open, activate it.
            figure(hd.maskFig)
        end
    end

    function traceChanged(src,~)
        if ~data.has('gait'), return; end
        invalidateSteps();
        hd = data.gait.hd;
        traceType = lower(src.Value);
        switch traceType
            case 'x'
                ylabel(hd.ax, 'X (cm)')
            case 'y'
                ylabel(hd.ax, 'Y (cm)')
            case 'speed'
                ylabel(hd.ax, 'Speed (cm/s)')
        end

        % Recalculate only the selected paw for this trace.
        plotTrace();
        getSteps();
        plotSteps();
    end

    function updateInfo()
        updateTitle();
        if data.has('gait')
            invalidateSteps();
            getSpeeds()
            plotTrace()
            getSteps()
            plotSteps()
        end
    end

    function openSTA(~, ~)
        mousePos = get(0, 'PointerLocation');
        hd = data.gait.hd;
        if ~isfield(hd, 'sta_GUI') || ~isgraphics(hd.sta_GUI, 'figure')
            hd.sta_GUI = gait.sta_GUI(mousePos);
            data.gait.hd = hd;
            notify(data, 'WindowsChanged');
        else
            figure(hd.sta_GUI);
        end
    end

    function pawChanged(~,~)
        invalidateSteps();
        plotTrace();
        getSteps();
        plotSteps();
    end

    function pawThreshChanged(~,~)
        if ~data.has('gait'), return; end
        invalidateSteps();
        hd = data.gait.hd;

        % save changed value. No more auto value after manually changed
        pawIdx = hd.pawList.Value;
        traceType = lower(hd.trace.Value);
        data.gait.paw(pawIdx).thresh.(traceType) = hd.pawthresh.Value;

        % update threhold line
        data.gait.hd = shared.myPlot(@yline, hd, 'pawThresLine', hd.ax, ...
                [], hd.pawthresh.Value, ...
                'b:', 'HitTest', 'off');

        % redo gait analysis.
        getSteps();
        plotSteps();
    end

    function intervalChanged(~,~)
        if ~data.has('gait'), return; end
        getSteps(); plotSteps();
    end

    function stepChanged(~,~)
        updateIntervalField();
        plotSteps();
    end

    function stepCheckChanged(src,~)
        if ~data.has('gait'), return; end
        if src.Value && ~gait.steps_current(data), invalidateSteps(); return; end
        plotSteps();   % shows or hides markers here and in the other viewers
    end

    % === sync time and zoom ===========
    function axClicked(~,evt)
        data.setTime(evt.IntersectionPoint(1));
    end
    
    function updateGaitTime(currentTime)
        hd = data.gait.hd;
        if data.has('gait')
            set(hd.timeline, 'Value', currentTime);
    
            zoomlim = shared.zoom(get(hd.ax,'xLim'), currentTime, 'pan');
            data.setZoom(zoomlim);
        end
    end
    
    function zoomIn(~, ~)
        hd = data.gait.hd;
        zoomlim = shared.zoom(get(hd.ax,'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end
    
    function zoomOut(~, ~)
        hd = data.gait.hd;
        zoomlim = shared.zoom(get(hd.ax,'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end
    
    function axZoomChanged(src,~)
        data.setZoom(src.Limits);
    end

    function refresh(~,~)
        if ~data.has('gait'), return; end
        t = data.gait.t(isfinite(data.gait.t));
        if numel(t)>1, data.setZoom(t([1 end])); end
        ylim(data.gait.hd.ax, 'auto');   % also undo vertical zoom

        updateInfo();
    end

    function exportAxes(~,~)        
        ax = data.gait.hd.ax;
        f = figure();
        ax2 = copyobj(ax, f);
        ax2.Units = 'normalized';
        ax2.Position = [0 0 1 1];
    end
    
    function updateGaitZoom(newZoom)
        hd = data.gait.hd;
        if data.has('gait')
            newZoom(1) = max([0 newZoom(1)]);
            newZoom(2) = min([newZoom(2) max(data.gait.t, [], 'omitnan')]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end
    
    % === follow edits in the Pose viewer ===========
    % Only when the paws were imported from the Pose viewer. Prompt once on
    % the first relevant change; ignore further changes until answered.
    function onPoseChanged(evt)
        if posePromptPending || ~data.has('gait'), return; end
        if ~isfield(data.gait, 'source') || ~strcmp(data.gait.source, 'pose_module'), return; end
        if ~ismember(evt.Kind, {'open', 'edit', 'commit'}), return; end
        pawNames = {data.gait.paw.name};
        changed = intersect(evt.Bodyparts, pawNames, 'stable');
        if isempty(changed), return; end

        posePromptPending = true;
        if strcmp(evt.Kind, 'open')
            what = 'A new pose file was opened in the Pose viewer.';
        else
            what = sprintf('Pose data changed for: %s.', strjoin(changed, ', '));
        end
        msg = sprintf(['%s\n\nUpdate the gait paws from the Pose viewer, or keep the ' ...
            'copy imported earlier?\nUpdate also includes any pose changes made ' ...
            'while this message is open.'], what);
        uiconfirm(fig, msg, 'Pose changed', ...
            'Options', {'Update', 'Keep'}, 'DefaultOption', 1, 'CancelOption', 2, ...
            'Icon', 'question', 'CloseFcn', @onPoseAnswer);
    end

    function onPoseAnswer(~, evt)
        posePromptPending = false;
        if strcmp(evt.SelectedOption, 'Update'), updatePawsFromPose(); end
    end

    % Re-copy every imported paw from the current pose table, keeping the
    % thresholds, then recalculate.
    function updatePawsFromPose()
        if ~data.has('gait'), return; end
        if ~data.has('pose')
            uialert(fig, 'The Pose viewer has no data. The gait paws were kept.', 'Update');
            return;
        end
        tablePose = data.pose.table;
        nOld = numel(data.gait.paw(1).rawX);
        missing = {};
        for ii = 1:numel(data.gait.paw)
            name = data.gait.paw(ii).name;
            if all(ismember({[name '_x'], [name '_y']}, tablePose.Properties.VariableNames))
                data.gait.paw(ii).rawX = tablePose.([name '_x']);
                data.gait.paw(ii).rawY = tablePose.([name '_y']);
            else
                missing{end+1} = name; %#ok<AGROW>
            end
        end
        notes = {};
        if ~isempty(missing)
            notes{end+1} = sprintf('Not found in the pose data, kept unchanged: %s.', ...
                strjoin(missing, ', '));
        end
        if height(tablePose) ~= nOld
            if ~isempty(missing)
                % paws of different lengths cannot share one time base
                uialert(fig, sprintf(['The pose data has %d frames, the gait data %d, and ' ...
                    'some paws are missing. Import Pose again instead.'], ...
                    height(tablePose), nOld), 'Update failed');
                return;
            end
            % frame count changed: the mask no longer fits, start over
            data.gait.mask = true(height(tablePose), 1);
            if isfield(data.gait, 'maskTemp'), data.gait = rmfield(data.gait, 'maskTemp'); end
            if isfield(data.gait, 'maskTempSpeed'), data.gait = rmfield(data.gait, 'maskTempSpeed'); end
            notes{end+1} = 'The number of frames changed, so the mask was reset.';
        end
        updateInfo();
        if ~isempty(notes)
            uialert(fig, strjoin(notes, newline), 'Update', 'Icon', 'warning');
        end
    end

    % close function =================================
    function onClose(src,~)
        if ~shared.confirm_close(fig, 'gait'), return; end
        shared.remember_position('gait', fig);
        hd = data.gait.hd;

        % Clear data and graphic handles first
        data.gait = struct();
        data.fig = rmfield(data.fig, 'gait');
        
        % Clear all the handles and plots;
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

        notify(data, 'GaitChanged');   % other viewers remove their step markers
        delete(src);  % finally close the GUI
        data.moduleClosed();
    end

end 