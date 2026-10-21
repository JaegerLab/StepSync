function fig = gait_viewer()

    data = shared.SessionData.instance();
    % true while the "DLC changed" prompt is open; further DLCChanged
    % events are ignored until the user answers it.
    dlcPromptPending = false;
    drawGUI()

    function drawGUI()
        hd = struct;
        % gait viewer window with uigridlayout
        fig = uifigure('Name', 'Gait Viewer', 'Position', [100 100 1000 500], ...
            'CloseRequestFcn',@onClose);
        data.fig(1).gait = fig;
        shared.MenuBar(fig, {'Open', []; 'Import DLC', @importPaws; 'Save', []});
        drawnow
        grid1 = uigridlayout(fig, Padding = [20,20,20,20], ...
            ColumnWidth = {'1x', 140}, RowHeight = {30, '1x', 30});

        %% Row 1: DLC processing
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0], ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 1));
        subgrid1.ColumnWidth = {'1x', 130,130,130,120,120};
        hd.info = uilabel(subgrid1,'Text',' Info:', 'BackgroundColor','w');
        hd.frameRate = uieditfield(subgrid1,'numeric','Value',1, ...
            'ValueDisplayFormat','Frame rate: %.2f Hz', 'Editable','off');
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

        hd.trace = uidropdown(grid1, 'Items',{'X', 'Y', 'Speed'}, 'Value', 'X', ...
            'ValueChangedFcn', @traceChanged, ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));


        %% Row 2: DLC plot
        hd.ax = uiaxes(grid1); hold(hd.ax, 'on');
        hd.ax.ButtonDownFcn = @axClicked;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        hd.ax.Layout.Row = [2 3]; hd.ax.Layout.Column = 1;
        ylabel(hd.ax, 'X (cm)'); xlabel(hd.ax, 'Time (s)')
        disableDefaultInteractivity(hd.ax)

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
        hd.dlcListener = addlistener(data, 'DLCChanged', @(~,evt)onDLCChanged(evt));

        data.gait(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    function importPaws(~,~)
        hd = data.gait.hd;
        if ~data.has('dlc')
            % no dlc data, read dlc from file.
            [filename, pathname]=uigetfile(fullfile(data.defaultPath, '*.csv'), 'Open DeepLabCut file');
            if isequal(pathname,0), return; end
            filename=fullfile(pathname, filename);
            if ~exist(filename, "file"), return; end
            data.rememberPath(filename);

            table_dlc = DLC.read_dlc(filename);
            part_list = table_dlc.Properties.UserData;
            dlcFile = filename;
            source = filename;
        else
            % read dlc from dlc_viewer
            table_dlc = data.dlc.table;
            part_list = data.dlc.hd.list_bodyparts.Items;
            dlcFile = '';
            if isfield(data.dlc, 'filename'), dlcFile = data.dlc.filename; end
            source = 'dlc_module';  % follow later DLC edits (see onDLCChanged)
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
        data.gait.source = source;
        data.gait.filename = dlcFile;   % shown in the title
        dlcPromptPending = false;
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
        updateTitle();
    end

    % The title shows the DLC file the paws were imported from.
    function updateTitle()
        fig.Name = 'Gait Viewer';
        if data.has('gait') && isfield(data.gait, 'filename') && ~isempty(data.gait.filename)
            fig.Name = ['Gait Viewer: ' data.gait.filename];
        end
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
        data.gait.t = data.getFrameTimes(numel(data.gait.paw(1).raw_x));
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
    % viewers (via GAIT.current_steps) never read gait's UI controls.
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
            [nearZero, restInfo] = GAIT.auto_rest_threshold(trace, data.getFrameRate());
            data.gait.paw(pawIdx).nearZeroStatus = restInfo.status;
            hd.stepList.Tooltip = sprintf('Near-zero: %.3g cm/s. %s',nearZero,restInfo.status);
        end
        data.gait.paw(pawIdx).nearZeroThreshold = nearZero;
        interval = max(1, round(hd.minTimeInterval.Value * data.getFrameRate()));
        detectionMask = data.gait.mask & isfinite(data.gait.t);
        steps = GAIT.detect_steps(trace, detectionMask, threshold, interval, nearZero);
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

    function previewChanged()
        if data.has('gait'), plotTrace(); end
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
    % theirs from GAIT.current_steps(data).
    function plotSteps()
        syncSelection();
        hd = data.gait.hd;
        if GAIT.steps_current(data) && data.gait.selection.show
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
            data.gait.hd.maskFig = GAIT.mask_GUI(mousePos);
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
            hd.sta_GUI = GAIT.sta_GUI(mousePos);
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
        plotSteps();
    end

    function stepCheckChanged(src,~)
        if ~data.has('gait'), return; end
        if src.Value && ~GAIT.steps_current(data), invalidateSteps(); return; end
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
    
    % === follow edits in the DLC viewer ===========
    % Only when the paws were imported from the DLC viewer. Prompt once on
    % the first relevant change; ignore further changes until answered.
    function onDLCChanged(evt)
        if dlcPromptPending || ~data.has('gait'), return; end
        if ~isfield(data.gait, 'source') || ~strcmp(data.gait.source, 'dlc_module'), return; end
        if ~ismember(evt.Kind, {'open', 'edit', 'commit'}), return; end
        pawNames = {data.gait.paw.name};
        changed = intersect(evt.Bodyparts, pawNames, 'stable');
        if isempty(changed), return; end

        dlcPromptPending = true;
        if strcmp(evt.Kind, 'open')
            what = 'A new DLC file was opened in the DLC viewer.';
        else
            what = sprintf('DLC data changed for: %s.', strjoin(changed, ', '));
        end
        msg = sprintf(['%s\n\nUpdate the gait paws from the DLC viewer, or keep the ' ...
            'copy imported earlier?\nUpdate also includes any DLC changes made ' ...
            'while this message is open.'], what);
        uiconfirm(fig, msg, 'DLC changed', ...
            'Options', {'Update', 'Keep'}, 'DefaultOption', 1, 'CancelOption', 2, ...
            'Icon', 'question', 'CloseFcn', @onDLCAnswer);
    end

    function onDLCAnswer(~, evt)
        dlcPromptPending = false;
        if strcmp(evt.SelectedOption, 'Update'), updatePawsFromDLC(); end
    end

    % Re-copy every imported paw from the current DLC table, keeping the
    % thresholds, then recalculate.
    function updatePawsFromDLC()
        if ~data.has('gait'), return; end
        if ~data.has('dlc')
            uialert(fig, 'The DLC viewer has no data. The gait paws were kept.', 'Update');
            return;
        end
        table_dlc = data.dlc.table;
        nOld = numel(data.gait.paw(1).raw_x);
        missing = {};
        for ii = 1:numel(data.gait.paw)
            name = data.gait.paw(ii).name;
            if all(ismember({[name '_x'], [name '_y']}, table_dlc.Properties.VariableNames))
                data.gait.paw(ii).raw_x = table_dlc.([name '_x']);
                data.gait.paw(ii).raw_y = table_dlc.([name '_y']);
            else
                missing{end+1} = name; %#ok<AGROW>
            end
        end
        notes = {};
        if ~isempty(missing)
            notes{end+1} = sprintf('Not found in the DLC data, kept unchanged: %s.', ...
                strjoin(missing, ', '));
        end
        if height(table_dlc) ~= nOld
            if ~isempty(missing)
                % paws of different lengths cannot share one time base
                uialert(fig, sprintf(['The DLC data has %d frames, the gait data %d, and ' ...
                    'some paws are missing. Import DLC again instead.'], ...
                    height(table_dlc), nOld), 'Update failed');
                return;
            end
            % frame count changed: the mask no longer fits, start over
            data.gait.mask = true(height(table_dlc), 1);
            if isfield(data.gait, 'maskTemp'), data.gait = rmfield(data.gait, 'maskTemp'); end
            notes{end+1} = 'The number of frames changed, so the mask was reset.';
        end
        updateInfo();
        if ~isempty(notes)
            uialert(fig, strjoin(notes, newline), 'Update', 'Icon', 'warning');
        end
    end

    % close function =================================
    function onClose(src,~)
        if ~shared.confirm_close(fig, 'Gait Viewer'), return; end
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