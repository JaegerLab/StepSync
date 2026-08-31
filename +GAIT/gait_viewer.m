function fig = gait_viewer(default_path)

    data = shared.SessionData.instance();
    hd = struct;
    drawGUI(default_path)
    data.gait(1).hd = hd;
    
    function drawGUI(default_path)
    
        % gait viewer window with uigridlayout
        fig = uifigure('Name', 'Gait Viewer', 'Position', [100 100 1000 400], ...
            'CloseRequestFcn',@onClose);
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
            'ValueDisplayFormat','Resolution: %d px/cm');
        hd.pawthresh = uieditfield(subgrid1,'numeric','Value',10, ...
            'ValueDisplayFormat','Paw thresh: %.2f cm/s', ...
            'ValueChangedFcn', @pawThreshChanged);
        hd.minTimeInterval = uieditfield(subgrid1,'numeric','Value',0.2, ...
            'ValueDisplayFormat','Min interval: %.2f s', ...
            'ValueChangedFcn', @pawThreshChanged);
        
        uibutton(subgrid1, 'Text', 'Edit Mask', 'ButtonPushedFcn', @openMask);

        hd.trace = uidropdown(grid1, 'Items',{'X', 'Y', 'Speed'}, 'Value', 'Speed', ...
            'ValueChangedFcn', @traceChanged);

        
        %% Row 3: DLC plot
        hd.ax = uiaxes(grid1); 
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
            hd.poiCheck = uicheckbox(subgrid4, Text='Steps', Value=1, ...
                Enable='off', ValueChangedFcn=@poiCheckChanged);
            hd.poiNum = uieditfield(subgrid4, 'numeric', Value = 0, Editable='off');
        hd.poiList = uilistbox(subgrid3, 'Multiselect', 'off', ...
            'ValueChangedFcn', @poiChanged, 'Enable','off');
        hd.sta = uibutton(subgrid3, Text='Step Triggered Avg', Enable='off', ...
                ButtonPushedFcn=@plotSTA);

        %% Row 4: zoom in, zoom out, update buttons
        subgrid2 = uigridlayout(grid1, [1 3], 'Padding', [0 0 0 0]);
        subgrid2.Layout.Row = 4; subgrid2.Layout.Column = 2;
        uibutton(subgrid2,'Text','🔍︎+','ButtonPushedFcn',@zoomIn);
        uibutton(subgrid2,'Text','🔍︎-','ButtonPushedFcn',@zoomOut);
        uibutton(subgrid2,'Text','⭮','ButtonPushedFcn',@(src,evt)updateInfo());

        data.gait(1).hd = hd;
    end

    function importPaws(~,~)
        if ~data.has('dlc')
            % read dlc from file.
            filename = hd.path.Value;
            [filename, pathname]=uigetfile(filename, 'Open DeepLabCut file');
            if isequal(pathname,0), return; end
            filename=fullfile(pathname, filename);
            if ~exist(filename, "file"), return; end
            hd.path.Value = pathname;
        
            data.dlc.table = DLC.read_dlc(filename);
        else
            hd.path.Value = data.dlc.hd.path.Value;
        end

        % get bodypart list
        part_list = data.dlc.hd.list_bodyparts.Items;
        
        % select paws
        [pawIdx, tf] = listdlg('PromptString','Select paws:','ListString',part_list);
        if ~tf, return; end

        % add selected body parts into GUI lists
        hd.pawList.Items = part_list(pawIdx); hd.pawList.Enable = 'on';
        hd.pawList.ItemsData = 1:numel(pawIdx);

        % add listeners
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateGaitTime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateGaitZoom(src.currentZoom));
        hd.dataListener = addlistener(data, 'DataChanged', @(~,~)gaitAnalysis());
        hd.infoListener = addlistener(data, 'InfoChanged', @(~,~)updateInfo());

        % enable POIs
        hd.poiCheck.Enable = 'on';
        hd.sta.Enable = 'on';
        hd.poiList.Enable = 'on';
        hd.poiList.Items = {'rising','falling','onset','offset','peak','valley'};

        data.gait.hd = hd;

        getSpeeds();
        plotTraces();
        gaitAnalysis();
    end

    function getSpeeds()
        hd.frameRate.Value = data.getFrameRate;
        data.gait.speedFactor = hd.frameRate.Value / hd.resolution.Value;

        for ii = 1:numel(hd.pawList.Items)                
            data.gait.paw(ii).name = hd.pawList.Items{ii};
            x = data.dlc.table.([data.gait.paw(ii).name '_x']);
            y = data.dlc.table.([data.gait.paw(ii).name '_y']);
            paw_speed = GAIT.smooth_speed(x, y, 3).*data.gait.speedFactor;

            data.gait.paw(ii).x = x./hd.resolution.Value;
            data.gait.paw(ii).y = y./hd.resolution.Value;
            data.gait.paw(ii).speed = paw_speed;
        end
    end
   
    function plotTraces()
        hold(hd.ax, 'on');
        data.gait.t = data.dlc.t;

        % paw speed
        pawIdx = hd.pawList.Value;
        t = data.gait.t;
        switch hd.trace.Value
            case 'X'
                trace = data.gait.paw(pawIdx).x;
            case 'Y'
                trace = data.gait.paw(pawIdx).y;
            case 'Speed'
                trace = data.gait.paw(pawIdx).speed;
        end
        data.gait.paw(pawIdx).trace = trace;
        data.gait.paw(pawIdx).traceType = hd.trace.Value;
        % paw speed masked
        if isfield(data.gait, 'maskTemp')
            mask = data.gait.maskTemp;
        elseif isfield(data.gait, 'mask')
            mask = data.gait.mask;
        else
            data.gait.mask = true(size(trace));
            mask = data.gait.mask;
        end
        unmask = ~mask | circshift(~mask, 1) | circshift(~mask, -1);

        % unmasked
        if any(unmask)
            t_unmask = t; t_unmask(~unmask)=NaN;
            trace_unmask = trace; trace_unmask(~unmask) = NaN;
            hd = shared.myPlot(@plot, hd, 'pawUnmask', hd.ax, ...
                    t_unmask, trace_unmask, ...
                    'Color', '#AAAACC', 'ButtonDownFcn', @axClicked);
        end
        % masked
        t_mask = t; t_mask(~mask) = NaN;
        trace_mask = trace; trace_mask(~mask) = NaN;        
        hd = shared.myPlot(@plot, hd, 'pawMask', hd.ax, ...
                        t_mask, trace_mask, ...
                        'Color', '#0000CC', 'ButtonDownFcn', @axClicked);

        % threshold lines
        autoThresh()
        hd = shared.myPlot(@yline, hd, 'pawThresLine', hd.ax, ...
                        [], hd.pawthresh.Value, ...
                        'b:', 'HitTest', 'off');

        % time line
        hd = shared.myPlot(@xline, hd, 'timeline', hd.ax, ...
                        data.currentTime, [], ...
                        'k-', 'HitTest', 'off');

        data.gait.hd = hd;
    end

    function getPOIs()
        pawthres = hd.pawthresh.Value;

        MinTimeInterval = round(hd.minTimeInterval.Value*data.getFrameRate());
        MaxRestingSpeed = 2.5;
        MaxSpeedLimit = 50;

        for ii = 1:numel(data.gait.paw)
            trace = data.gait.paw(ii).trace;
            if isfield(data.gait, 'mask')
                trace(~data.gait.mask) = NaN;
            end
            
            % find the first index of each no move period.
            % insert noMove to break up the non-continuous pawups and pawdowns.
            noMoveIdx = find(diff(~data.gait.mask)==1) + 1 ;
            data.gait.paw(ii).noMove = noMoveIdx;

            % rising 
            riseIdx = find(trace(1:end-1)<=pawthres & trace(2:end)>pawthres);
            data.gait.paw(ii).rising = riseIdx;
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
            data.gait.paw(ii).onset = unique(riseIdx(~isnan(riseIdx)));

            % falling
            fallIdx = find(trace(1:end-1)>pawthres & trace(2:end)<=pawthres)+1;
            data.gait.paw(ii).falling = fallIdx;
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
            data.gait.paw(ii).offset = unique(fallIdx(~isnan(fallIdx)));
        
            % peak and maxspeed
            [peakValue,peakIdx] = findpeaks(trace, ...
                "MinPeakProminence", std(trace), ...
                "MinPeakDistance", MinTimeInterval); 
            invalid = peakValue<pawthres;
            peakIdx(invalid)=[];
            peakValue(invalid)=[];
            data.gait.paw(ii).peak = peakIdx;
            data.gait.paw(ii).maxSpeed = peakValue;
            
            % valley
            [~,valleyIdx] = findpeaks(70-trace, ...
                'MinPeakProminence', std(trace), ...
                "MinPeakDistance", MinTimeInterval); 
            invalid = trace(valleyIdx) > pawthres;
            valleyIdx(invalid)=[];
            data.gait.paw(ii).valley = valleyIdx;

        end
    end

    function plotPOIs()
        if hd.poiCheck.Value && isequal(hd.poiCheck.Enable, 'on')
            % paw POIs
            pawIdx = hd.pawList.Value;
            poiName = hd.poiList.Value;
            poiIdx = data.gait.paw(pawIdx).(poiName);
            poiT = data.gait.t(poiIdx);
            poiX = data.gait.paw(pawIdx).x(poiIdx)*hd.resolution.Value;
            poiY = data.gait.paw(pawIdx).y(poiIdx)*hd.resolution.Value;

            % numbers of gait step points.
            hd.poiNum.Value = length(poiIdx);
                
            linespec = {'mo', 'LineWidth', 2};
            hd = shared.myPlot(@scatter, hd, 'poiGait', hd.ax, ...
                            poiT, hd.pawMask.YData(poiIdx), ...
                            linespec{:});
    
            if data.has('emg')
                hd = shared.myPlot(@scatter, hd, 'poiEMG', data.emg.hd.ax, ...
                                poiT, zeros(size(poiT)), linespec{:});
            end
    
            if data.has('dlc')
                hd = shared.myPlot(@scatter, hd, 'poiXDLC', data.dlc.hd.ax, ...
                                poiT, poiX, linespec{:});
                hd.poiXDLC.Visible = data.dlc.hd.chk_x.Value;
                hd = shared.myPlot(@scatter, hd, 'poiYDLC', data.dlc.hd.ax, ...
                                poiT, poiY, linespec{:});
                hd.poiYDLC.Visible = data.dlc.hd.chk_y.Value;
            end
    
            if data.has('video') 
                hd = shared.myPlot(@scatter, hd, 'poiVideo', data.video.hd.ax, ...
                                poiX, poiY, linespec{:});
                timeWindow = 1;
                alpha(hd.poiVideo, 2./(1 + exp(abs(poiT-data.currentTime)/timeWindow)));
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
        switch src.Value
            case 'X'
                ylabel(hd.ax, 'X (cm)')
            case 'Y'
                ylabel(hd.ax, 'Y (cm)')
            case 'Speed'
                ylabel(hd.ax, 'Speed (cm/s)')
        end
        plotTraces();
        gaitAnalysis();
    end

    function autoThresh()
        pawIdx = hd.pawList.Value;
        hd.pawthresh.Value = mean(data.gait.paw(pawIdx).trace);
    end

    function updateInfo()
        getSpeeds()
        plotTraces()
        % gaitAnalysis()
        % plotPOIs()
    end

    function gaitAnalysis()
        % getSpeeds();
        getPOIs();
        plotPOIs();
    end

    function plotSTA(~,~)
        if ~data.has('emg')
            uialert(fig, 'Requires EMG', 'Error');
            return;
        end

        channel = data.emg.hd.chanList.Value;
        emgType = data.emg.hd.datatype.Value;
        if strcmp(emgType, "Raw")
            emg = data.emg.analog_data(:,channel);
            emgT = data.emg.t;
        else
            emg = data.emg.processed.data(:,channel);
            emgT = data.emg.processed.t;
        end
        
        pawIdx = hd.pawList.Value;
        poiName = hd.poiList.Value;
        poiIdx = data.gait.paw(pawIdx).(poiName);
        poiT = data.gait.t(poiIdx);
        
        [ydata, xdata, info] = GAIT.sta(emg, emgT, poiT, 'plot', data.gait);

        sta = info;
        sta.ydata = ydata;
        sta.xdata = xdata;
        sta.emgType = emgType;
        sta.emgChan = channel;
        idx = data.emg.hd.chanList.ItemsData == channel;
        sta.emgChanName = data.emg.hd.chanList.Items{idx};
        sta.pawName = data.gait.paw(pawIdx).name;
        sta.poiName = poiName;
        sta.traceName = hd.trace.Value;

        title(sta.axis, [sta.pawName ', ' poiName ' on ' sta.traceName ', ' sta.emgChanName], ...
            "Interpreter","none");

        data.gait.sta = sta;
        assignin('base', 'sta', sta);
    end

    function pawChanged(~,~)
        getSpeeds();
        plotTraces();
        plotPOIs();
    end

    function pawThreshChanged(~,~)
        hd = shared.myPlot(@yline, hd, 'pawThresLine', hd.ax, ...
                        [], hd.pawthresh.Value, ...
                        'b:', 'HitTest', 'off');
        gaitAnalysis();
    end

    function poiChanged(~,~)
        plotPOIs();
    end

    function poiCheckChanged(src,~)
        handles = {'poiGait','poiEMG','poiXDLC','poiYDLC','poiVideo'};
        for k=1:numel(handles)
            if isfield(hd, handles{k}) && ishghandle(hd.(handles{k}))
                hd.(handles{k}).Visible = src.Value;
            end
        end
        if src.Value
            plotPOIs();
        end
    end

    % === sync time and zoom ===========
    function axClicked(~,evt)
        data.setTime(evt.IntersectionPoint(1));
    end
    
    function updateGaitTime(currentTime)
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
        if isfield(hd, 'poiVideo') && ishghandle(hd.poiVideo)
            poiIdx = data.gait.paw(hd.pawList.Value).(hd.poiList.Value);
            poiT = data.gait.t(poiIdx);
            set(hd.poiVideo, ...
                "AlphaData", 2./(1 + exp(abs(poiT-currentTime))) );
        end
    end
    
    function zoomIn(~, ~)
        zoomlim = shared.zoom(get(hd.ax,'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end
    
    function zoomOut(~, ~)
        zoomlim = shared.zoom(get(hd.ax,'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end
    
    function axZoomChanged(src,~)
        data.setZoom(src.Limits);
    end
    
    function updateGaitZoom(newZoom)
        if data.has('gait')
            newZoom(1) = max([0 newZoom(1)]);
            newZoom(2) = min([newZoom(2) data.gait.t(end)]);
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end
    
    % close function =================================
    function onClose(src,~)
        
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

        % Clear data and graphic handles
        data.gait = struct();
    
        data.fig = rmfield(data.fig, 'gait');
        delete(src);  % finally close the GUI
    end

end 