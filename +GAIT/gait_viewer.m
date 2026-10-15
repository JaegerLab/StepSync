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
            'ValueChangedFcn', @pawThreshChanged);
        
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
        % traceType = lower(hd.trace.Value);

        for ii = 1:numel(hd.pawList.Items)    
            paw = data.gait.paw(ii);

            % convert raw xy (in pixels) to xy (in centimeters)
            data.gait.paw(ii).x = paw.raw_x./hd.resolution.Value;
            data.gait.paw(ii).y = paw.raw_y./hd.resolution.Value;
            
            % calculate speed in cm/s
            data.gait.paw(ii).speed = ...
                GAIT.smooth_speed(paw.raw_x, paw.raw_y, 3) .* ...
                data.gait.speedFactor;

            % data.gait.paw(ii).trace = data.gait.paw(ii).(traceType);
            % data.gait.paw(ii).traceType = traceType;
        end
        % reconstruct t
        data.gait.t = (1:length(paw.x))'./hd.frameRate.Value;
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
        unmask = ~mask;

        % plot unmasked as grey blue
        if any(unmask)
            % Expand unmask 1 datapoint so there're no gaps.
            unmask = unmask | unmask([1 1:end-1]) | unmask([2:end end]);
            t_unmask = t; t_unmask(~unmask) = NaN;
            trace_unmask = trace; trace_unmask(~unmask) = NaN;
            hd = shared.myPlot(@plot, hd, 'pawUnmask', hd.ax, ...
                    t_unmask, trace_unmask, ...
                    'Color', '#AAAACC', 'HitTest', 'off');
        end
        % plot masked as deep blue
        if any(mask)
            t_mask = t; t_mask(~mask) = NaN;
            trace_mask = trace; trace_mask(~mask) = NaN;        
            hd = shared.myPlot(@plot, hd, 'pawMask', hd.ax, ...
                    t_mask, trace_mask, ...
                    'Color', '#0000CC', 'HitTest', 'off');
        end

        % plot threshold line
        thresh = data.gait.paw(pawIdx).thresh.(traceType); %get saved value
        if isnan(thresh) % default is NaN
            thresh = mean(trace); % Auto threshold unless manually changed
        end
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

    function getSteps()
        hd = data.gait.hd;

        MinTimeInterval = round(hd.minTimeInterval.Value*data.getFrameRate());
        MaxRestingSpeed = 2.5;
        % MaxSpeedLimit = 50;

        % only calculate the current paw steps instead of all paws.
        pawIdx = hd.pawList.Value;
        % for ii = 1:numel(data.gait.paw)

            traceType = lower(hd.trace.Value);
            trace = data.gait.paw(pawIdx).(traceType);
            data.gait.paw(pawIdx).traceType = traceType;
            
            if isfield(data.gait, 'mask')
                trace(~data.gait.mask) = NaN;
            end
            
            thresh = data.gait.paw(pawIdx).thresh.(traceType); %get saved value
            if isnan(thresh) % default is NaN
                thresh = mean(trace); % Auto threshold unless manually changed
            end

            % find the first index of each no move period.
            % insert noMove to break up the non-continuous pawups and pawdowns.
            noMoveIdx = find(diff(~data.gait.mask)==1) + 1 ;
            data.gait.paw(pawIdx).noMove = noMoveIdx;

            % rising 
            riseIdx = find(trace(1:end-1)<=thresh & trace(2:end)>thresh);
            data.gait.paw(pawIdx).rising = riseIdx;
            % find the point almost zero BEFORE the threshold-crossing point
            for k=1:length(riseIdx)
                range = riseIdx(k)+(-MinTimeInterval:0);
                range(range<=0)=[];
                offset = find(trace(range) <= MaxRestingSpeed, 1,"last");
                if offset
                    riseIdx(k) = riseIdx(k) - MinTimeInterval + offset;
                else 
                    riseIdx(k) = NaN;
                end
            end
            data.gait.paw(pawIdx).onset = unique(riseIdx(~isnan(riseIdx)));

            % falling
            fallIdx = find(trace(1:end-1)>thresh & trace(2:end)<=thresh)+1;
            data.gait.paw(pawIdx).falling = fallIdx;
            % find the point almost zero AFTER the threshold-crossing point
            for k=1:length(fallIdx)
                range = fallIdx(k)+(0:MinTimeInterval);
                range(range>length(trace))=[];
                offset = find(trace(range) <= MaxRestingSpeed, 1,"first");
                if offset
                    fallIdx(k) = fallIdx(k) + offset;
                else 
                    fallIdx(k) = NaN;
                end
            end
            data.gait.paw(pawIdx).offset = unique(fallIdx(~isnan(fallIdx)));
        
            % peak and maxspeed
            [peakValue,peakIdx] = findpeaks(trace, ...
                "MinPeakProminence", std(trace, 'omitnan'), ...
                "MinPeakDistance", MinTimeInterval); 
            invalid = peakValue<thresh;
            peakIdx(invalid)=[];
            peakValue(invalid)=[];
            data.gait.paw(pawIdx).peak = peakIdx;
            data.gait.paw(pawIdx).maxSpeed = peakValue;
            
            % valley
            [~,valleyIdx] = findpeaks(-trace, ...
                'MinPeakProminence', std(trace, 'omitnan'), ...
                "MinPeakDistance", MinTimeInterval); 
            invalid = trace(valleyIdx) > thresh;
            valleyIdx(invalid)=[];
            data.gait.paw(pawIdx).valley = valleyIdx;
        % end
    end

    function plotSteps()
        hd = data.gait.hd;
        if hd.stepCheck.Value && isequal(hd.stepCheck.Enable, 'on')
            % paw Steps
            pawIdx = hd.pawList.Value;
            stepName = hd.stepList.Value;
            stepIdx = data.gait.paw(pawIdx).(stepName);
            stepT = data.gait.t(stepIdx);
            stepX = data.gait.paw(pawIdx).x(stepIdx)*hd.resolution.Value;
            stepY = data.gait.paw(pawIdx).y(stepIdx)*hd.resolution.Value;

            % numbers of gait step points.
            hd.stepNum.Value = length(stepIdx);
                
            linespec = {'mo', 'LineWidth', 2};
            hd = shared.myPlot(@scatter, hd, 'stepGait', hd.ax, ...
                            stepT, hd.pawMask.YData(stepIdx), ...
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
                alpha(hd.stepVideo, 2./(1 + exp(abs(stepT-data.currentTime)/timeWindow)));
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

        % % change trace for all the paws.
        % for ii = 1:numel(hd.pawList.Items)    
        %     data.gait.paw(ii).trace = data.gait.paw(ii).(traceType);
        %     data.gait.paw(ii).traceType = traceType;
        % end

        % recalculate steps for all the paws.
        plotTrace();
        getSteps();
        plotSteps();
    end

    function updateInfo()
        if data.has('gait')
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
        plotTrace();
        getSteps();
        plotSteps();
    end

    function pawThreshChanged(~,~)
        hd = data.gait.hd;

        % save changed value. No more auto value after manually changed
        pawIdx = hd.pawList.Value;
        traceType = data.gait.paw(pawIdx).traceType;
        data.gait.paw(pawIdx).thresh.(traceType) = hd.pawthresh.Value;

        % update threhold line
        data.gait.hd = shared.myPlot(@yline, hd, 'pawThresLine', hd.ax, ...
                [], hd.pawthresh.Value, ...
                'b:', 'HitTest', 'off');

        % redo gait analysis.
        getSteps();
        plotSteps();
    end

    function stepChanged(~,~)
        plotSteps();
    end

    function stepCheckChanged(src,~)
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