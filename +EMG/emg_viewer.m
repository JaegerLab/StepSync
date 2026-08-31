function fig = emg_viewer(default_path)
    % App state
    data = shared.SessionData.instance();
    
    drawGUI(default_path);

    function drawGUI(default_path)
        % EMG viewer window with uigridlayout
        fig = uifigure('Name', 'EMG Viewer', 'Position', [100 100 1000 500], ...
            'CloseRequestFcn', @onClose);
        drawnow
        grid1 = uigridlayout(fig, ...
            'RowHeight', {30, 30, '1x', 30}, ...
            'ColumnWidth',{'1x', 140});
        
        
        %% Row 1: Folder and open button
        hd.path = uieditfield(grid1, 'text'); 
        if nargin>=1
            hd.path.Value = default_path;
        end
        uibutton(grid1, 'Text', 'Open EMG', 'ButtonPushedFcn', @openEMG);
    
        %% Row 2: Preprocess group
        subgrid1 = uigridlayout(grid1, [1 5], 'Padding', [0 0 0 0]);
        subgrid1.ColumnWidth = {'1x', 120, 100, 100, 100};
            hd.info = uilabel(subgrid1, 'Text', 'Sample Rate (Hz):');
            uibutton(subgrid1, 'Text', 'Push Frame Rate', 'ButtonPushedFcn', @pushFrameRate);
            hd.time = uieditfield(subgrid1,'numeric','Value',0, ...
                    'ValueDisplayFormat', 'time: %.3f s');
            uibutton(subgrid1, 'Text', 'Pre-Process', 'ButtonPushedFcn', @preprocess);
            hd.datatype = uidropdown(subgrid1, "Items", "Raw", "ValueChangedFcn", @typeChanged);

        uibutton(grid1, 'Text', 'Load Channel Map', 'ButtonPushedFcn', @(src,evt)loadChannelMap()); 
    
        %% Row 3: Listbox + Axes
        hd.ax = uiaxes(grid1);
        hold(hd.ax, "on"); axis(hd.ax, 'tight');
        hd.ax.Layout.Row = [3 4]; hd.ax.Layout.Column = 1;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        xlabel(hd.ax, 'Time (s)'); ylabel(hd.ax, 'Voltage');
        disableDefaultInteractivity(hd.ax)
    
        subgrid3 = uigridlayout(grid1, [2 1], Padding=[0 0 0 0], ...
            RowHeight={'1x', 30});
        subgrid3.Layout.Row = 3; subgrid3.Layout.Column = 2;
            hd.chanList = uilistbox(subgrid3, 'Multiselect', 'off', ...
                'ValueChangedFcn', @(src,evt)updatePlots());
            subgrid4 = uigridlayout(subgrid3, [1 2], Padding = [0 0 0 0], ...
                        ColumnWidth ={50, '1x'});
            uilabel(subgrid4, 'Text', 'Sort by:');
            hd.sortby = uidropdown(subgrid4, 'Enable', 'off', ...
                "Items",["Channel", "Muscle"], 'ValueChangedFcn', @(src,evt)sortChannelMap());
        

        %% Row 4: zoom in, zoom out, update buttons
        subgrid2 = uigridlayout(grid1, [1 3], 'Padding', [0 0 0 0]);
        uibutton(subgrid2,'Text','🔍︎+','ButtonPushedFcn',@zoomIn);
        uibutton(subgrid2,'Text','🔍︎-','ButtonPushedFcn',@zoomOut);
        uibutton(subgrid2,'Text','⭮','ButtonPushedFcn',@(src,evt)updatePlots());

        % add listeners
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateEMGtime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateEMGzoom(src.currentZoom));
        hd.dataListener = addlistener(data, 'DataChanged', @(src, evt)updatePlots());
        hd.InfoListener = addlistener(data, 'InfoChanged', @(src, evt)updateInfo());

        data.emg(1).hd = hd;
    end

    %% === Load EMG the first time === %%
    function openEMG(~, ~)
        hd = data.emg.hd;
        % open file----------------
        % == new UI, select the folder, compatible with Open Ephys ===
        pathname = uigetdir(hd.path.Value, 'Select the Directory for EMG data files');
        if isequal(pathname, 0), return; end

        emgData = EMG.emg_read(pathname);

        % Update state ---------------
        data.emg.filename = emgData.files;
        data.emg.display_name = pathname;
        data.emg.analog_data = emgData.analog_data;
        data.emg.analog_channels = emgData.analog_channels;
        data.emg.sample_rate = emgData.sample_rate;
        if isfield(emgData, 'dig_in_data')
            % Intan
            data.emg.trigger.data = emgData.dig_in_data;
        elseif isfield(emgData, 'trigger')
            % Open Ephys
            data.emg.trigger = emgData.trigger;
        end
        data.emg.t = emgData.t;

        hd.datatype.Items = "Raw";
        hd.sortby.Enable = 'off';

        updateInfo();
        updatePlots();
    end

    % separate reading and updating info, because reading is slow, and
    % data is saved in SessionData. No need to repeat reading for update.
    function updateInfo()
        if ~data.has('emg'); return; end
        
        hd = data.emg.hd;
        % trigger time
        if isfield(data.emg, 'trigger')
            if ~isfield(data.emg.trigger, 'time')
                data.emg.trigger.time = data.emg.t(1 + find(diff(data.emg.trigger.data)>0.5));
            end
            data.emg.trigger.freq = 1/median(diff(data.emg.trigger.time));
            data.emg.trigger.number = length(data.emg.trigger.time);
        end

        % Update UI -------------------
        hd.path.Value = data.emg.display_name;
        hd.chanList.Items = data.emg.analog_channels;
        hd.chanList.ItemsData = 1:length(data.emg.analog_channels);

        hd.info.Text = sprintf( ...
            'Rate: %d Hz, Length: %.2f s\nTrigger#: %d, Freq: %.2f Hz', ...
            data.emg.sample_rate, data.emg.t(end), ...
            data.emg.trigger.number, data.emg.trigger.freq);
    end

    function pushFrameRate(~,~)
        data.frameRate = data.emg.trigger.freq;
        notify(data, 'InfoChanged');
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
    end

    function loadChannelMap()
        % get default fileter
        hd = data.emg.hd;
        default_file = hd.path.Value;
        if isempty(default_file)
            default_file='*.csv';
        else
            path = fileparts(default_file);
            default_file = fullfile(path, '*.csv');
        end
        % select file
        [file, path] = uigetfile(default_file, 'Select Channel Mapping File', 'MultiSelect', 'off');
        filename = fullfile(path, file);
        if isequal(path,0) || ~exist(filename, "file"), return; end
        
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
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end

    % close function
    function onClose(~,~)
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
    end

end
