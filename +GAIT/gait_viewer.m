function fig = gait_viewer(default_path)

    data = shared.SessionData.instance();
    drawGUI(default_path)
    
    function drawGUI(default_path)
        hd = struct;
        % gait viewer window with uigridlayout
        fig = uifigure('Name', 'Gait Viewer', 'Position', [100 100 1000 500], ...
            'CloseRequestFcn',@onClose);
        data.fig(1).gait = fig;
        drawnow
        grid1 = uigridlayout(fig, Padding = [20,20,20,20], ...
            ColumnWidth = {'1x', 140}, RowHeight = {30, 30, '1x', 30});

        %% Row 1: Folder and open button
        hd.path = uieditfield(grid1, 'text'); 
        if nargin>=1
            hd.path.Value = default_path;
        end
        uibutton(grid1, 'Text', 'Import DLC', 'ButtonPushedFcn', @importPaws);
        
        %% Row 2: DLC processing
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0], ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 2, 'Column', 1));
        subgrid1.ColumnWidth = {'1x', 130,130,130,120,120};
        hd.info = uilabel(subgrid1,'Text',' Info:', 'BackgroundColor','w');
        hd.frameRate = uieditfield(subgrid1,'numeric','Value',1, ...
            'ValueDisplayFormat','Frame rate: %.2f Hz');
        hd.resolution = uieditfield(subgrid1,'numeric','Value',30, ...
            'ValueDisplayFormat','Resolution: %d px/cm', ...
            'ValueChangedFcn', @(~,~)updateInfo);
        hd.pawthresh = uieditfield(subgrid1,'numeric','Value',10, ...
            'ValueDisplayFormat','Paw thresh: %.2f cm/s', ...
            'ValueChangedFcn', @pawThreshChanged);
        hd.minTimeInterval = uieditfield(subgrid1,'numeric','Value',0.2, ...
            'ValueDisplayFormat','Min interval: %.2f s', ...
            'Limits', [0 Inf], 'LowerLimitInclusive', 'off', ...
            'ValueChangedFcn', @intervalChanged);
        
        uibutton(subgrid1, 'Text', 'Edit Mask', 'ButtonPushedFcn', @openMask);

        hd.trace = uidropdown(grid1, 'Items',{'X', 'Y', 'Speed'}, 'Value', 'X', ...
            'ValueChangedFcn', @traceChanged);

        
        %% Row 3: DLC plot
        hd.ax = uiaxes(grid1); hold(hd.ax, 'on');
        hd.ax.ButtonDownFcn = @axClicked;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        hd.ax.Layout.Row = [3 4]; hd.ax.Layout.Column = 1;
        ylabel(hd.ax, 'Speed (cm/s)'); xlabel(hd.ax, 'Time (s)')
        disableDefaultInteractivity(hd.ax)

        subgrid3 = uigridlayout(grid1, [4 1], Padding = [0 0 0 0], ...
            RowHeight={'1x', 30, '1x', 30});
        subgrid3.Layout.Row = 3; subgrid3.Layout.Column = 2;
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

        %% Row 4: zoom in, zoom out, update buttons
        subgrid2 = uigridlayout(grid1, [1 4], 'Padding', [0 0 0 0]);
        subgrid2.Layout.Row = 4; subgrid2.Layout.Column = 2;
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
        hd.dataListener = addlistener(data, 'DataChanged', @(~,~)updateInfo());
        hd.infoListener = addlistener(data, 'InfoChanged', @(~,~)updateInfo());

        data.gait(1).hd = hd;
    end

    function importPaws(~,~)
        hd = data.gait.hd;
        if ~data.has('dlc')
            % no dlc data, read dlc from file.
            filename = hd.path.Value;
            [filename, pathname]=uigetfile(filename, 'Open DeepLabCut file');
            if isequal(pathname,0), return; end
            filename=fullfile(pathname, filename);
            if ~exist(filename, "file"), return; end
        
            table_dlc = DLC.read_dlc(filename);
            part_list = table_dlc.Properties.UserData;
            hd.path.Value = pathname;
        else
            % read dlc from dlc_viewer
            table_dlc = data.dlc.table;
            part_list = data.dlc.hd.list_bodyparts.Items;
            hd.path.Value = data.dlc.hd.path.Value;
        end
        
        % select paws
        [pawIdx, tf] = listdlg('PromptString','Select paws:','ListString',part_list);
        drawnow; figure(fig);
        if ~tf, return; end

        % add selected body parts into GUI lists
        hd.pawList.Items = part_list(pawIdx); hd.pawList.Enable = 'on';
        hd.pawList.ItemsData = 1:numel(pawIdx);

        % save raw x, y in pixels, 
        % so that later no need to read from dlc when frame rate changes.
        for field = {'maskFig','sta_GUI'}
            if isfield(hd, field{1}) && isgraphics(hd.(field{1})), close(hd.(field{1})); end
        end
        invalidateSteps();
        oldHd = data.gait.hd;
        data.gait = struct('hd', oldHd);
        for ii = 1:numel(hd.pawList.Items) 
            pawName = hd.pawList.Items{ii};
            data.gait.paw(ii).name = pawName;
            data.gait.paw(ii).raw_x = table_dlc.([pawName '_x']);
            data.gait.paw(ii).raw_y = table_dlc.([pawName '_y']);
            data.gait.paw(ii).thresh = struct('x',NaN,'y',NaN,'speed',NaN);
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
    end

    function getSpeeds()
        hd = data.gait.hd;
        hd.frameRate.Value = data.getFrameRate;
        data.gait.speedFactor = hd.frameRate.Value / hd.resolution.Value;

        for ii = 1:numel(hd.pawList.Items)    
            paw = data.gait.paw(ii);

            % convert raw xy (in pixels) to xy (in centimeters)
            data.gait.paw(ii).x = paw.raw_x./hd.resolution.Value;
            data.gait.paw(ii).y = paw.raw_y./hd.resolution.Value;
            
            % calculate speed in cm/s
            data.gait.paw(ii).speed = ...
                GAIT.smooth_speed(paw.raw_x, paw.raw_y, 3) .* ...
                data.gait.speedFactor;

        end
        % reconstruct t
        data.gait.t = (1:numel(data.gait.paw(1).raw_x))'./hd.frameRate.Value;
    end
   
    function plotTrace()
        hd = data.gait.hd;
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
            error('GAIT:maskSize', 'Mask and trace sizes differ.');
        end
        mask = logical(mask(:));
        unmask = ~mask;

        % Always replace both traces, including empty selections.
        unmask = unmask | unmask([1 1:end-1]) | unmask([2:end end]);
        trace_unmask = trace; trace_unmask(~unmask) = NaN;
        trace_mask = trace; trace_mask(~mask) = NaN;
        hd = shared.myPlot(@plot, hd, 'pawUnmask', hd.ax, t, trace_unmask, ...
            'Color', '#AAAACC', 'HitTest', 'off');
        hd = shared.myPlot(@plot, hd, 'pawMask', hd.ax, t, trace_mask, ...
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

        data.gait.hd = hd;
    end

    function invalidateSteps()
        data.gait.stepsValid = false;
        hd = data.gait.hd;
        handles = {'stepGait','stepEMG','stepXDLC','stepYDLC','stepVideo'};
        for k = 1:numel(handles)
            if isfield(hd, handles{k}) && isgraphics(hd.(handles{k}))
                hd.(handles{k}).Visible = 'off';
            end
        end
        hd.stepNum.Value = 0;
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
        hd = data.gait.hd;
        pawIdx = hd.pawList.Value;
        traceType = lower(hd.trace.Value);
        trace = data.gait.paw(pawIdx).(traceType);
        threshold = selectedThreshold(trace, pawIdx, traceType);
        interval = max(1, round(hd.minTimeInterval.Value * data.getFrameRate()));
        steps = GAIT.detect_steps(trace, data.gait.mask, threshold, interval);
        % Commit only after every event type has been calculated successfully.
        fields = fieldnames(steps);
        for k = 1:numel(fields)
            data.gait.paw(pawIdx).(fields{k}) = steps.(fields{k});
        end
        data.gait.paw(pawIdx).traceType = traceType;
        data.gait.stepsPaw = pawIdx;
        data.gait.stepsTrace = traceType;
        data.gait.stepsValid = true;
    end

    function plotSteps()
        hd = data.gait.hd;
        if GAIT.steps_current(data) && ...
                hd.stepCheck.Value && isequal(hd.stepCheck.Enable, 'on')
            % paw Steps
            pawIdx = hd.pawList.Value;
            stepName = hd.stepList.Value;
            stepIdx = data.gait.paw(pawIdx).(stepName);
            stepT = data.gait.t(stepIdx);
            stepX = data.gait.paw(pawIdx).x(stepIdx)*hd.resolution.Value;
            stepY = data.gait.paw(pawIdx).y(stepIdx)*hd.resolution.Value;

            % numbers of gait step points.
            hd.stepNum.Value = length(stepIdx);
                
            selectedTrace = data.gait.paw(pawIdx).(lower(hd.trace.Value));
            linespec = {'Marker', 'o', 'MarkerEdgeColor', 'm', 'LineWidth', 2};
            hd = shared.myPlot(@scatter, hd, 'stepGait', hd.ax, ...
                            stepT, selectedTrace(stepIdx), ...
                            linespec{:}, 'HitTest', 'off');
    
            if data.has('emg')
                hd = shared.myPlot(@scatter, hd, 'stepEMG', data.emg.hd.ax, ...
                                stepT, zeros(size(stepT)), ...
                                linespec{:}, 'HitTest', 'off');
            end
    
            if data.has('dlc')
                hd = shared.myPlot(@scatter, hd, 'stepXDLC', data.dlc.hd.ax, ...
                                stepT, stepX, linespec{:}, 'HitTest', 'off');
                hd.stepXDLC.Visible = data.dlc.hd.chk_x.Value;
                hd = shared.myPlot(@scatter, hd, 'stepYDLC', data.dlc.hd.ax, ...
                                stepT, stepY, linespec{:}, 'HitTest', 'off');
                hd.stepYDLC.Visible = data.dlc.hd.chk_y.Value;
            end
    
            if data.has('video') 
                hd = shared.myPlot(@scatter, hd, 'stepVideo', data.video.hd.ax, ...
                                stepX, stepY, linespec{:}, 'HitTest', 'off');
                timeWindow = 1;
                set(hd.stepVideo, 'AlphaData', 2./(1 + exp(abs(stepT-data.currentTime)/timeWindow)), ...
                    'MarkerEdgeAlpha', 'flat');
            end
    
            for field = {'stepGait','stepEMG','stepXDLC','stepYDLC','stepVideo'}
                if isfield(hd, field{1}) && isgraphics(hd.(field{1}))
                    hd.(field{1}).Visible = 'on';
                end
            end
            if isfield(hd, 'stepXDLC') && isgraphics(hd.stepXDLC)
                hd.stepXDLC.Visible = data.dlc.hd.chk_x.Value;
                hd.stepYDLC.Visible = data.dlc.hd.chk_y.Value;
            end
            data.gait.hd = hd;
        end
    end

    function openMask(~,~)
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.gait.hd;
        if ~isfield(hd, 'maskFig') || ~isgraphics(hd.maskFig, 'figure')
            % open a new window
            data.gait.hd.maskFig = GAIT.mask_GUI(mousePos);
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
            hd.sta_GUI = GAIT.sta_GUI(mousePos);
            data.gait.hd = hd;
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
        plotSteps();
    end

    function stepCheckChanged(src,~)
        if src.Value && ~GAIT.steps_current(data), invalidateSteps(); return; end
        hd = data.gait.hd;
        handles = {'stepGait','stepEMG','stepXDLC','stepYDLC','stepVideo'};
        for k=1:numel(handles)
            if isfield(hd, handles{k}) && ishghandle(hd.(handles{k}))
                hd.(handles{k}).Visible = src.Value;
            end
        end
        if src.Value
            plotSteps();
        end
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
    
            if data.has('video')
                updateVideoMarker(currentTime)
            end
        end
    end

    function updateVideoMarker(currentTime)
        if ~GAIT.steps_current(data), return; end
        hd = data.gait.hd;
        if isfield(hd, 'stepVideo') && ishghandle(hd.stepVideo)
            stepIdx = data.gait.paw(hd.pawList.Value).(hd.stepList.Value);
            stepT = data.gait.t(stepIdx);
            set(hd.stepVideo, ...
                "AlphaData", 2./(1 + exp(abs(stepT-currentTime))) );
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
        data.setZoom(data.gait.t([1 end]));

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
            newZoom(2) = min([newZoom(2) data.gait.t(end)]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end
    
    % close function =================================
    function onClose(src,~)
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

        delete(src);  % finally close the GUI
    end

end 