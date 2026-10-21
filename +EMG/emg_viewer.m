function fig = emg_viewer()
    % App state
    data = shared.SessionData.instance();

    drawGUI();

    function drawGUI()
        % EMG viewer window with uigridlayout
        fig = uifigure('Name', 'EMG Viewer', 'Position', [100 100 1000 500], ...
            'CloseRequestFcn', @onClose);
        data.fig(1).emg = fig;
        shared.MenuBar(fig, {'Open', @openEMG; 'Open .mat', []; 'Save', []});
        drawnow
        grid1 = uigridlayout(fig, ...
            'RowHeight', {30, '1x', 30}, ...
            'ColumnWidth',{'1x', 140});

        hd = struct();

        %% Row 1: Preprocess group
        subgrid1 = uigridlayout(grid1, [1 5], 'Padding', [0 0 0 0]);
        subgrid1.Layout.Row = 1; subgrid1.Layout.Column = 1;
        subgrid1.ColumnWidth = {'1x', 120, 100, 100, 100};
            hd.info = uilabel(subgrid1, 'Text', 'Sample Rate (Hz):');
            uibutton(subgrid1, 'Text', 'Push Frame Rate', 'ButtonPushedFcn', @pushFrameRate);
            hd.time = uieditfield(subgrid1,'numeric','Value',0, ...
                    'ValueDisplayFormat', 'time: %.3f s');
            uibutton(subgrid1, 'Text', 'Pre-Process', 'ButtonPushedFcn', @preprocess);
            hd.datatype = uidropdown(subgrid1, "Items", "Raw", "ValueChangedFcn", @typeChanged);

        uibutton(grid1, 'Text', 'Load Channel Map', 'ButtonPushedFcn', @(src,evt)loadChannelMap(), ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));

        %% Row 2: Listbox + Axes
        hd.ax = uiaxes(grid1);
        hold(hd.ax, "on");
        hd.ax.ButtonDownFcn = @axClicked;
        hd.ax.Layout.Row = [2 3]; hd.ax.Layout.Column = 1;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        xlabel(hd.ax, 'Time (s)'); ylabel(hd.ax, 'Voltage');
        disableDefaultInteractivity(hd.ax)
    
        subgrid3 = uigridlayout(grid1, [2 1], Padding=[0 0 0 0], ...
            RowHeight={'1x', 30});
        subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
            hd.chanList = uilistbox(subgrid3, 'Multiselect', 'off', ...
                'ValueChangedFcn', @(src,evt)updatePlots());
            subgrid4 = uigridlayout(subgrid3, [1 2], Padding = [0 0 0 0], ...
                        ColumnWidth ={50, '1x'});
            uilabel(subgrid4, 'Text', 'Sort by:');
            hd.sortby = uidropdown(subgrid4, 'Enable', 'off', ...
                "Items",["Channel", "Muscle"], 'ValueChangedFcn', @(src,evt)sortChannelMap());
        

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
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateEMGtime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateEMGzoom(src.currentZoom));
        hd.emgListener = addlistener(data, 'EMGChanged', @(src, evt)updatePlots());
        hd.gaitListener = addlistener(data, 'GaitChanged', @(src, evt)drawSteps());
        hd.InfoListener = addlistener(data, 'InfoChanged', @(src, evt)updateInfo());

        data.emg(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    %% === Load EMG the first time === %%
    function openEMG(~, ~)
        hd = data.emg.hd;
        % open file----------------
        % == new UI, select the folder, compatible with Open Ephys ===
        pathname = uigetdir(data.defaultPath, 'Select the Directory for EMG data files');
        drawnow; figure(fig);
        if isequal(pathname, 0), return; end
        data.rememberPath(pathname);

        try
            emgData = EMG.emg_read(pathname);
        catch ME
            drawnow; figure(fig);
            if strcmp(ME.identifier,'EMG:cancelled'), return; end
            rethrow(ME);
        end
        drawnow; figure(fig); % Return from reader dialogs (including Open Ephys TTL selection).

        if isfield(hd, 'prepGUI') && isgraphics(hd.prepGUI), close(hd.prepGUI); end
        % Replace recording-specific state, retaining only the live UI.
        data.emg = struct('hd', hd);
        % Update state ---------------
        data.emg.filename = emgData.files;
        data.emg.display_name = pathname;
        data.emg.analog_data = emgData.analog_data;
        data.emg.analog_channels = emgData.analog_channels;
        data.emg.sample_rate = emgData.sample_rate;
        data.emg.analog_units = 'uV';
        if isfield(emgData,'analog_units'), data.emg.analog_units = emgData.analog_units; end
        if isfield(emgData, 'dig_in_data')
            % Intan
            digital = emgData.dig_in_data;
            channel = 1;
            if size(digital, 2) > 1
                labels = cell(1, size(digital,2));
                for k = 1:size(digital,2)
                    times = emgData.t(1 + find(diff(digital(:,k)) > 0.5));
                    labels{k} = sprintf('Ch %d: %d TTL', k, numel(times));
                    intervals = diff(times);
                    intervals = intervals(isfinite(intervals) & intervals > 0);
                    if ~isempty(intervals)
                        labels{k} = sprintf('%s, %.3g Hz', labels{k}, 1/median(intervals));
                    end
                end
                [channel, ok] = listdlg('PromptString', 'Select camera TTL channel:', ...
                    'ListString', labels, 'SelectionMode', 'single', 'ListSize', [340 200]);
                drawnow; figure(fig);
                if ~ok, channel = []; end
            end
            if ~isempty(channel)
                data.emg.trigger.data = digital(:,channel);
                data.emg.trigger.time = emgData.t(1 + find(diff(digital(:,channel)) > 0.5));
            end
        elseif isfield(emgData, 'trigger')
            % Open Ephys
            data.emg.trigger = emgData.trigger;
        end
        data.emg.t = emgData.t;
        if isfield(data.emg, 'trigger')
            intervals = diff(data.emg.trigger.time);
            intervals = intervals(isfinite(intervals) & intervals > 0);
            data.emg.trigger.freq = NaN;
            if ~isempty(intervals), data.emg.trigger.freq = 1/median(intervals); end
            data.emg.trigger.number = numel(data.emg.trigger.time);
        end

        hd.datatype.Items = "Raw";
        hd.sortby.Enable = 'off';

        notify(data, 'InfoChanged');
        notify(data, 'EMGChanged');
        notify(data, 'TimeChanged');
    end

    % separate reading and updating info, because reading is slow, and
    % data is saved in SessionData. No need to repeat reading for update.
    function updateInfo()
        if ~data.has('emg'); return; end
        
        hd = data.emg.hd;
        
        if isfield(data.emg, 'trigger')
            triggerInfo = sprintf('Trigger#: %d, Freq: %.2f Hz', ...
                data.emg.trigger.number, data.emg.trigger.freq);
        else
            triggerInfo = "Camera trigger not found.";
        end

        % Update UI -------------------
        fig.Name = ['EMG Viewer: ' data.emg.display_name];
        if isfield(data.emg,'analog_units'), ylabel(hd.ax,['EMG (' data.emg.analog_units ')']); end
        selectedChannel = hd.chanList.Value;
        if isfield(data.emg, 'ch_mapping')
            [~, order] = sort(data.emg.ch_mapping.(hd.sortby.Value));
            hd.chanList.Items = data.emg.ch_mapping.Names(order);
            hd.chanList.ItemsData = order;
        else
            hd.chanList.Items = data.emg.analog_channels;
            hd.chanList.ItemsData = 1:length(data.emg.analog_channels);
        end
        if isnumeric(selectedChannel) && isscalar(selectedChannel) && ...
                ismember(selectedChannel, hd.chanList.ItemsData)
            hd.chanList.Value = selectedChannel;
        end

        hd.info.Text = sprintf( ...
            'Rate: %d Hz, Length: %.2f s\n%s', ...
            data.emg.sample_rate, data.emg.t(end), ...
            triggerInfo);
    end

    function pushFrameRate(~,~)
        if isfield(data.emg, 'trigger') && isfinite(data.emg.trigger.freq) && data.emg.trigger.freq > 0
            data.setFrameRate(data.emg.trigger.freq);
        end
    end

    %% main update
    function updatePlots()
        if ~data.has('emg'); return; end

        hd = data.emg.hd;
        channels = hd.chanList.Value;
        
        % raw plot
        if isequal(hd.datatype.Value, "Raw") ||  isfield(data.emg, 'temp')
            t = data.emg.t;
            y = data.emg.analog_data(:,channels);
            hd = shared.myPlot(@plot, hd, 'rawPlot', ...
                hd.ax, t, y, 'b-', 'ButtonDownFcn', @axClicked);
            hd.rawPlot.Visible = true;
        else 
            if isfield(hd, 'rawPlot') && ishghandle(hd.rawPlot)
                hd.rawPlot.Visible = false;
            end
        end
        % temp plot
        if isfield(data.emg, 'temp')
            t = data.emg.temp.t;
            y = data.emg.temp.data;
            hd = shared.myPlot(@plot, hd, 'tempPlot', ...
                hd.ax, t, y, 'y-', 'ButtonDownFcn', @axClicked);
            hd.tempPlot.Visible = true;
        else
            if isfield(hd, 'tempPlot') && ishghandle(hd.tempPlot)
                hd.tempPlot.Visible = false;
            end
        end
        % processed plot
        if isequal(hd.datatype.Value, "Processed") && isfield(data.emg, 'processed')
            t = data.emg.processed.t;
            y = data.emg.processed.data(:,channels);
            hd = shared.myPlot(@plot, hd, 'prosPlot', ...
                hd.ax, t, y, 'g-', 'ButtonDownFcn', @axClicked);
            hd.prosPlot.Visible = true;
        else
            if isfield(hd, 'prosPlot') && ishghandle(hd.prosPlot)
                hd.prosPlot.Visible = false;
            end
        end
        
        if isfield(hd, 'timeline') && ishghandle(hd.timeline)
            hd.timeline.Value = data.currentTime;
        else
            hd.timeline = xline(hd.ax, data.currentTime, 'k', 'HitTest','off');
        end
        data.emg.hd = hd;
        drawSteps();
    end

    % gait steps as markers on the time axis (y = 0)
    function drawSteps()
        if ~isfield(data.emg, 'hd'), return; end
        hd = data.emg.hd;
        steps = GAIT.current_steps(data);
        if data.has('emg') && ~isempty(steps) && ~isempty(steps.t)
            hd = shared.myPlot(@scatter, hd, 'stepMarker', hd.ax, ...
                steps.t, zeros(size(steps.t)), ...
                'Marker', 'o', 'MarkerEdgeColor', 'm', 'LineWidth', 2, 'HitTest', 'off');
            hd.stepMarker.Visible = 'on';
        elseif isfield(hd, 'stepMarker') && isgraphics(hd.stepMarker)
            hd.stepMarker.Visible = 'off';
        end
        data.emg.hd = hd;
    end

    function loadChannelMap()
        hd = data.emg.hd;
        % select file
        [file, path] = uigetfile(fullfile(data.defaultPath, '*.csv'), ...
            'Select Channel Mapping File', 'MultiSelect', 'off');
        if isequal(path,0), return; end
        drawnow; figure(fig);
        filename = fullfile(path, file);
        if ~exist(filename, "file"), return; end
        data.rememberPath(filename);
        
        % read channel mapping csv file
        ch_mapping = readtable(filename);
        % check if channel number is correct.
        if height(ch_mapping) == size(data.emg.analog_data, 2)
            % mono-pole recording
        elseif height(ch_mapping) == 2*size(data.emg.analog_data, 2)
            % differential recording
            ch_mapping = ch_mapping(1:2:end, :);
        else
            error('Channel number mismatch');
        end

        % add analog channel name to the mapping table.
        Analog = data.emg.analog_channels';
        ch_mapping = addvars(ch_mapping, Analog, 'before', 1);

        % add variable names to the sort by dropdown menu
        hd.sortby.Items = ch_mapping.Properties.VariableNames;
        hd.sortby.Enable = 'on';

        % combine table into channel names
        ch_mapping = convertvars(ch_mapping, @isnumeric, @(x)cellstr(num2str(x)));
        ch_mapping.Names = join(ch_mapping{:,:}, ', ');        
        data.emg.ch_mapping = ch_mapping;

        % save channel names in the list
        hd.chanList.Items = ch_mapping.Names;
        
        data.emg.hd = hd;
        sortChannelMap
    end

    function sortChannelMap()
        hd = data.emg.hd;
        [~, orders] = sort(data.emg.ch_mapping.(hd.sortby.Value));
        hd.chanList.Items = data.emg.ch_mapping.Names(orders);
        hd.chanList.ItemsData = orders;
    end

    %% pre-process data
    function preprocess(~,~)
        
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.emg.hd;

        if ~isfield(hd, 'prepGUI') || ~isgraphics(hd.prepGUI, 'figure')
            hd.prepGUI = EMG.emg_prep_GUI(mousePos);
            data.emg.hd = hd;
            notify(data, 'WindowsChanged');
        else
            % if window is already open, don't open another one.
            figure(hd.prepGUI)
        end
    end

    function typeChanged(~,~)
        updatePlots
    end

    %% sync figures' time and zoom between windows ========
    function axClicked(~,evt)
        data.setTime(evt.IntersectionPoint(1));
    end

    function updateEMGtime(currentTime)
        if data.has('emg')
            hd = data.emg.hd;
            hd.timeline.Value = currentTime;
            hd.time.Value = currentTime;
            zoomlim = shared.zoom(data.currentZoom, currentTime, 'pan');
            data.setZoom(zoomlim);
        end
    end

    function zoomIn(~, ~)
        zoomlim = shared.zoom(get(data.emg.hd.ax, 'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end

    function zoomOut(~, ~)
        zoomlim = shared.zoom(get(data.emg.hd.ax, 'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end

    function axZoomChanged(src, ~)
        data.setZoom(src.Limits);
    end

    function updateEMGzoom(newZoom)
        hd = data.emg.hd;
        if data.has('emg')
            newZoom(1)=max([0 newZoom(1)]);
            newZoom(2)=min([newZoom(2), data.emg.t(end)]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end

    function refresh(~,~)
        if ~data.has('emg'), return; end
        data.setZoom([0 data.emg.t(end)]);
        ylim(data.emg.hd.ax, 'auto');   % also undo vertical zoom

        updateInfo();
    end

    function exportAxes(~,~)        
        ax = data.emg.hd.ax;
        f = figure();
        ax2 = copyobj(ax, f);
        ax2.Units = 'normalized';
        ax2.Position = [0 0 1 1];
    end

    % close function
    function onClose(~,~)
        if ~shared.confirm_close(fig, 'EMG Viewer'), return; end
        hd = data.emg.hd;
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

        % Clear the data
        data.emg = struct();
        % Clear saved figure handle
        data.fig = rmfield(data.fig, 'emg');
        delete(fig);  % finally close the GUI
        data.moduleClosed();
    end

end
