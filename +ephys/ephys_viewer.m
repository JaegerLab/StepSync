function fig = ephys_viewer()
    % App state
    data = shared.SessionData.instance();

    drawGUI();

    function drawGUI()
        % Ephys viewer window with uigridlayout
        fig = uifigure('Name', 'StepSync Ephys', 'Position', shared.window_position('ephys', [100 100 1000 500]), ...
            'CloseRequestFcn', @onClose);
        data.fig(1).ephys = fig;
        shared.MenuBar(fig, {'Open File', @openFile; 'Open folder', @openFolder; 'Save', @saveEphys});
        drawnow
        grid1 = uigridlayout(fig, ...
            'RowHeight', {30, '1x', 30}, ...
            'ColumnWidth',{'1x', 140});

        hd = struct();

        %% Row 1: Preprocess group
        subgrid1 = uigridlayout(grid1, [1 6], 'Padding', [0 0 0 0]);
        subgrid1.Layout.Row = 1; subgrid1.Layout.Column = 1;
        subgrid1.ColumnWidth = {'1x', 230, 100, 100, 110, 30};
            hd.info = uilabel(subgrid1, 'Text', 'Sample Rate (Hz):');
            % camera trigger: digital channels, item 0 is no trigger
            hd.trigger = uidropdown(subgrid1, 'Items', {'No data'}, 'ItemsData', 0, ...
                'Enable', 'off', 'ValueChangedFcn', @triggerChanged);
            hd.time = uieditfield(subgrid1,'numeric','Value',0, ...
                    'ValueDisplayFormat', 'time: %.3f s');
            uibutton(subgrid1, 'Text', 'Pre-Process', 'ButtonPushedFcn', @preprocess);
            % data types: Raw, Processed 1..N (see ephys.ephys_types)
            hd.datatype = uidropdown(subgrid1, 'Items', {}, 'Placeholder', 'no data', ...
                'ValueChangedFcn', @typeChanged);
            hd.deleteType = uibutton(subgrid1, 'Text', '✕', 'Enable', 'off', ...
                'Tooltip', 'Delete the selected data type', 'ButtonPushedFcn', @deleteType);

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
            hd.chanList = uilistbox(subgrid3, 'Multiselect', 'off', 'Enable', 'off', ...
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
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateEphysTime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateEphysZoom(src.currentZoom));
        hd.ephysListener = addlistener(data, 'EphysChanged', @(src, evt)updatePlots());
        hd.gaitListener = addlistener(data, 'GaitChanged', @(src, evt)drawSteps());
        hd.InfoListener = addlistener(data, 'InfoChanged', @(src, evt)updateInfo());

        data.ephys(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    %% === Open a recording folder (Intan or Open Ephys) === %%
    function openFolder(~, ~)
        pathname = uigetdir(data.defaultPath, 'Select the Directory for ephys data files');
        drawnow; figure(fig);
        if isequal(pathname, 0), return; end
        data.rememberPath(pathname);
        loadRecording(@()ephys.ephys_read(pathname), pathname);
    end

    %% === Open Intan file(s) or a .mat file written by Save === %%
    function openFile(~, ~)
        [files, path] = uigetfile({'*.rhd;*.rhs', 'Intan files (*.rhd, *.rhs)'; ...
                                   '*.mat',       'MAT-files (*.mat)'; ...
                                   '*.*',         'All files (*.*)'}, ...
            'Open Ephys file(s)', data.defaultPath, 'MultiSelect', 'on');
        drawnow; figure(fig);
        if isequal(files, 0), return; end
        files = fullfile(path, cellstr(files));
        % All files lets anything through
        if ~all(endsWith(lower(files), {'.rhd', '.rhs', '.mat'}))
            uialert(fig, 'Select .rhd, .rhs or .mat files.', 'Open File');
            return;
        end
        isMat = endsWith(lower(files), '.mat');
        if any(isMat)
            if numel(files) > 1
                uialert(fig, 'Select a single .mat file, or one or more Intan files.', 'Open File');
                return;
            end
            openMat(files{1});
            return;
        end
        data.rememberPath(files{1});
        displayName = files{1};
        if numel(files) > 1, displayName = path; end
        loadRecording(@()ephys.read_intan(files), displayName);
    end

    %% === Load a recording read by readFcn, replacing the current ephys data === %%
    function loadRecording(readFcn, displayName)
        hd = data.ephys.hd;
        try
            recording = readFcn();
        catch ME
            drawnow; figure(fig);
            if ismember(ME.identifier, {'ephys:cancelled', 'ephys:missingReader'}), return; end
            rethrow(ME);
        end
        drawnow; figure(fig); % Return from reader dialogs (including Open Ephys TTL selection).

        if isfield(hd, 'prepGUI') && isgraphics(hd.prepGUI), close(hd.prepGUI); end
        % Replace recording-specific state, retaining only the live UI.
        data.ephys = struct('hd', hd);
        % Update state ---------------
        % reader outputs keep their names; data goes to raw / processed
        data.ephys.filename = recording.files;
        data.ephys.displayName = displayName;
        data.ephys.raw = struct('data', recording.analogData, 't', recording.t, ...
            'sampleRate', recording.sampleRate);
        data.ephys.processed = struct('data', {}, 't', {}, 'sampleRate', {}, 'parameters', {});
        data.ephys.analogChannels = recording.analogChannels;
        data.ephys.analogUnits = 'uV';
        if isfield(recording,'analogUnits'), data.ephys.analogUnits = recording.analogUnits; end
        % digital channels as edge times; the trigger is picked in hd.trigger
        data.ephys.digital = struct('name', {}, 'rise', {}, 'fall', {});
        if isfield(recording, 'digInData')
            % Intan
            names = {};
            if isfield(recording, 'digInChannels')
                names = {recording.digInChannels.native_channel_name};
            end
            data.ephys.digital = ephys.ttl_channels(recording.t, recording.digInData, names);
        elseif isfield(recording, 'digital')
            % Open Ephys
            data.ephys.digital = recording.digital;
        end

        hd.datatype.Items = ephys.ephys_types(data.ephys);
        hd.sortby.Enable = 'off';
        hd.chanList.Enable = 'on';

        notify(data, 'InfoChanged');
        notify(data, 'EphysChanged');
        notify(data, 'TimeChanged');
    end

    %% === Open a .mat file written by Save === %%
    % Replaces the current ephys data entirely. Raw data can be left out.
    function openMat(filename)
        try
            [names, bytes] = ephys.ephys_file_contents(filename);
        catch ME
            uialert(fig, ME.message, 'Open File');
            return;
        end
        if isempty(names)
            uialert(fig, 'The file contains no ephys data.', 'Open File');
            return;
        end
        labels = arrayfun(@(k)sprintf('%s (%.1f MB)', names{k}, bytes(k)/2^20), ...
            1:numel(names), 'UniformOutput', false);
        [selected, ok] = listdlg('Name', 'Open Ephys', 'PromptString', 'Data to load:', ...
            'ListString', labels, 'SelectionMode', 'multiple', ...
            'InitialValue', 1:numel(names), 'ListSize', [260 150]);
        drawnow; figure(fig);
        if ~ok || isempty(selected), return; end
        data.rememberPath(filename);

        hd = data.ephys.hd;
        if isfield(hd, 'prepGUI') && isgraphics(hd.prepGUI), close(hd.prepGUI); end
        ephysData = ephys.load_ephys(filename, names(selected));
        ephysData.hd = hd;
        ephysData.sourceFile = filename;   % Save may not overwrite it
        ephysData.displayName = filename;
        data.ephys = ephysData;

        types = ephys.ephys_types(data.ephys);
        hd.datatype.Items = types;
        if ~isempty(types), hd.datatype.Value = types{1}; end
        if isfield(data.ephys, 'chMapping')
            hd.sortby.Items = setdiff(data.ephys.chMapping.Properties.VariableNames, {'Names'}, 'stable');
            hd.sortby.Enable = 'on';
        else
            hd.sortby.Enable = 'off';
        end
        hd.chanList.Enable = 'on';

        notify(data, 'InfoChanged');
        notify(data, 'EphysChanged');
        notify(data, 'TimeChanged');
    end

    %% === Save the selected data types as a .mat file === %%
    function saveEphys(~, ~)
        if ~data.has('ephys')
            uialert(fig, 'There is no ephys data to save.', 'Save');
            return;
        end
        types = ephys.ephys_types(data.ephys);
        selected = types;
        if numel(types) > 1
            [idx, ok] = listdlg('Name', 'Save Ephys', 'PromptString', 'Data to save:', ...
                'ListString', types, 'SelectionMode', 'multiple', ...
                'InitialValue', 1:numel(types), 'ListSize', [200 120]);
            drawnow; figure(fig);
            if ~ok || isempty(idx), return; end
            selected = types(idx);
        end
        [range, ok] = shared.ask_save_range(fig, 'Ephys');
        if ~ok, return; end
        [~, base] = fileparts(data.ephys.displayName);
        [file, path] = uiputfile('*.mat', 'Save Ephys', ...
            fullfile(data.defaultPath, [base '_StepSync.mat']));
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        if isOriginal(filename)
            uialert(fig, sprintf('%s is the file this ephys data was opened from. Choose another name.', file), ...
                'Save refused');
            return;
        end

        progbar = uiprogressdlg(fig, 'Title', 'Saving', 'Message', 'Saving ephys data', ...
            'Indeterminate', 'on');
        closeBar = onCleanup(@()delete(progbar));   % also on errors
        ephys.save_ephys(filename, data.ephys, selected, range);
        clear closeBar
        data.rememberPath(filename);
        data.ephys.displayName = filename;   % the title shows the saved file
        updateInfo();
    end

    % true for a file the current ephys data was read from
    function tf = isOriginal(filename)
        originals = {};
        if isfield(data.ephys, 'filename'), originals = cellstr(data.ephys.filename); end
        if isfield(data.ephys, 'sourceFile'), originals{end+1} = data.ephys.sourceFile; end
        tf = any(strcmpi(filename, originals));
    end

    %% === Delete the selected data type === %%
    function deleteType(~, ~)
        hd = data.ephys.hd;
        label = hd.datatype.Value;
        types = ephys.ephys_types(data.ephys);
        if ~any(strcmp(label, types)), return; end
        if strcmp(label, 'Raw')
            msg = 'Delete the raw ephys data? Only opening the recording again brings it back.';
        else
            msg = sprintf('Delete %s?', label);
        end
        answer = uiconfirm(fig, msg, 'Delete', 'Options', {'Delete', 'Cancel'}, ...
            'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if ~strcmp(answer, 'Delete'), return; end

        idx = find(strcmp(label, types));
        data.ephys = ephys.ephys_delete(data.ephys, label);
        types = ephys.ephys_types(data.ephys);
        hd.datatype.Items = types;
        if ~isempty(types) 
            hd.datatype.Value = types{min(idx, end)}; 
        else
            hd.chanList.Enable = 'off';
        end
        notify(data, 'EphysChanged');
        updateInfo();
    end

    % Selected data type, or [] without data.
    function src = currentSource()
        src = [];
        if ~data.has('ephys'), return; end
        types = ephys.ephys_types(data.ephys);
        label = data.ephys.hd.datatype.Value;
        if ~any(strcmp(label, types)), label = types{1}; end
        src = ephys.ephys_source(data.ephys, label);
    end

    % Keep the dropdown in step with the data; no deleting while the
    % pre-process window is open.
    function updateTypes()
        hd = data.ephys.hd;
        types = ephys.ephys_types(data.ephys);
        selected = hd.datatype.Value;
        hd.datatype.Items = types;
        if any(strcmp(selected, types))
            hd.datatype.Value = selected;
        elseif ~isempty(types)
            hd.datatype.Value = types{1};
        end
        prepOpen = isfield(hd, 'prepGUI') && isgraphics(hd.prepGUI);
        hd.deleteType.Enable = ~isempty(types) && ~prepOpen;
    end

    % separate reading and updating info, because reading is slow, and
    % data is saved in SessionData. No need to repeat reading for update.
    function updateInfo()
        if ~isfield(data.ephys, 'hd'), return; end
        updateTriggerList();
        if ~data.has('ephys')
            % all data deleted: the metadata (trigger) is kept
            if isfield(data.ephys, 'analogChannels'), data.ephys.hd.info.Text = 'No ephys data.'; end
            return;
        end

        hd = data.ephys.hd;
        
        if isfield(data.ephys, 'trigger')
            triggerInfo = sprintf('Trigger#: %d, Freq: %.2f Hz', ...
                data.ephys.trigger.number, data.ephys.trigger.freq);
        else
            triggerInfo = "No camera trigger selected.";
        end

        % Update UI -------------------
        fig.Name = ['StepSync Ephys: ' data.ephys.displayName];
        if isfield(data.ephys,'analogUnits'), ylabel(hd.ax,['Ephys (' data.ephys.analogUnits ')']); end
        selectedChannel = hd.chanList.Value;
        if isfield(data.ephys, 'chMapping')
            [~, order] = sort(data.ephys.chMapping.(hd.sortby.Value));
            hd.chanList.Items = data.ephys.chMapping.Names(order);
            hd.chanList.ItemsData = order;
        else
            hd.chanList.Items = data.ephys.analogChannels;
            hd.chanList.ItemsData = 1:length(data.ephys.analogChannels);
        end
        if isnumeric(selectedChannel) && isscalar(selectedChannel) && ...
                ismember(selectedChannel, hd.chanList.ItemsData)
            hd.chanList.Value = selectedChannel;
        end

        % rate and length of the selected data type
        src = currentSource();
        hd.info.Text = sprintf( ...
            'Rate: %g Hz, Length: %.2f s\n%s', ...
            src.sampleRate, src.t(end), ...
            triggerInfo);
    end

    %% === Camera trigger === %%
    % Items: 'Select trigger channel' (0, no trigger), then one per digital channel.
    function updateTriggerList()
        hd = data.ephys.hd;
        if ~isfield(data.ephys, 'digital')
            if isfield(data.ephys, 'trigger')
                % a file saved before the channel list was kept
                set(hd.trigger, 'Items', {sprintf('Trigger: %d TTL, %.4g Hz', ...
                    data.ephys.trigger.number, data.ephys.trigger.freq)}, 'ItemsData', 0, 'Enable', 'off');
            else
                set(hd.trigger, 'Items', {'No data'}, 'ItemsData', 0, 'Enable', 'off');
            end
            return;
        end
        if isempty(data.ephys.digital)
            set(hd.trigger, 'Items', {'No digital channel'}, 'ItemsData', 0, 'Enable', 'off');
            return;
        end
        labels = arrayfun(@ephys.ttl_stats, data.ephys.digital, 'UniformOutput', false);
        set(hd.trigger, 'Items', [{'Select trigger channel'} labels], ...
            'ItemsData', 0:numel(labels), 'Enable', 'on');
        selected = 0;
        if isfield(data.ephys, 'trigger') && isfield(data.ephys.trigger, 'channel')
            selected = find(strcmp(data.ephys.trigger.channel, {data.ephys.digital.name}), 1);
            if isempty(selected), selected = 0; end
        end
        hd.trigger.Value = selected;
    end

    % Use the selected digital channel as the camera trigger: one rising
    % edge per frame of the open video, pose and gait data (one may be extra).
    function triggerChanged(src, evt)
        k = src.Value;
        if k == 0
            if isfield(data.ephys, 'trigger'), data.ephys = rmfield(data.ephys, 'trigger'); end
        else
            channel = data.ephys.digital(k);
            [~, s] = ephys.ttl_stats(channel);
            msg = '';
            if s.number < 2 || isnan(s.freq)
                msg = sprintf(['%s has %d TTL pulse(s), so it is not a camera trigger. ' ...
                    'A camera trigger has one pulse per frame.'], channel.name, s.number);
            else
                counts = data.frameCounts();
                modules = fieldnames(counts);
                bad = modules(cellfun(@(m)abs(counts.(m) - s.number) > 1, modules));
                if ~isempty(bad)
                    frames = cellfun(@(m)sprintf('%s: %d frames', upper(m), counts.(m)), ...
                        bad, 'UniformOutput', false);
                    msg = sprintf(['%s has %d TTL pulses, but the open data has a different ' ...
                        'number of frames (%s). A camera trigger has one pulse per frame.'], ...
                        channel.name, s.number, strjoin(frames, ', '));
                end
            end
            if ~isempty(msg)
                src.Value = evt.PreviousValue;
                uialert(fig, msg, 'Cannot synchronize');
                return;
            end
            data.ephys.trigger = struct('channel', channel.name, 'time', channel.rise, ...
                'freq', s.freq, 'number', s.number);
            % choosing a trigger replaces a typed-in frame rate
            data.frameRate = 0;
        end
        notify(data, 'InfoChanged');
        notify(data, 'TimeChanged');
    end

    %% main update
    function updatePlots()
        if ~isfield(data.ephys, 'hd'), return; end
        updateTypes();
        hd = data.ephys.hd;
        if ~data.has('ephys')
            hd = hidePlot(hd, 'dataPlot');
            hd = hidePlot(hd, 'tempPlot');
            data.ephys.hd = hd;
            drawSteps();
            return;
        end
        channels = hd.chanList.Value;

        % selected data type: raw blue, processed green
        src = currentSource();
        color = 'g';
        if strcmp(hd.datatype.Value, 'Raw'), color = 'b'; end
        hd = shared.myPlot(@plot, hd, 'dataPlot', hd.ax, ...
            src.t, src.data(:,channels), [color '-'], 'ButtonDownFcn', @axClicked);
        hd.dataPlot.Color = color;
        hd.dataPlot.Visible = true;
        % pre-process preview, over its source
        if isfield(data.ephys, 'temp')
            t = data.ephys.temp.t;
            y = data.ephys.temp.data;
            hd = shared.myPlot(@plot, hd, 'tempPlot', hd.ax, ...
                t, y, 'y-', 'ButtonDownFcn', @axClicked);
            hd.tempPlot.Visible = true;
        else
            hd = hidePlot(hd, 'tempPlot');
        end

        % draw timeline
        hd = shared.myPlot(@xline, hd, 'timeline', hd.ax, ...
            data.currentTime, [], 'k', 'HitTest','off');
        
        data.ephys.hd = hd;
        drawSteps();
    end

    function hd = hidePlot(hd, field)
        if isfield(hd, field) && ishghandle(hd.(field))
            hd.(field).Visible = false;
        end
    end

    % gait steps as markers on the ephys trace
    function drawSteps()
        if ~isfield(data.ephys, 'hd'), return; end
        hd = data.ephys.hd;
        steps = gait.current_steps(data);
        if data.has('ephys') && ~isempty(steps) && ~isempty(steps.t) && ...
                ~isempty(hd.chanList.Value)
            src = currentSource();
            y = interp1(src.t, src.data(:,hd.chanList.Value), steps.t, 'linear');
            hd = shared.myPlot(@scatter, hd, 'stepMarker', hd.ax, ...
                steps.t, y, ...
                'Marker', 'o', 'MarkerEdgeColor', 'm', 'LineWidth', 2, 'HitTest', 'off');
            hd.stepMarker.Visible = 'on';
            uistack(hd.stepMarker, "top");
        elseif isfield(hd, 'stepMarker') && isgraphics(hd.stepMarker)
            hd.stepMarker.Visible = 'off';
        end
        data.ephys.hd = hd;
    end

    function loadChannelMap()
        hd = data.ephys.hd;
        if ~isfield(data.ephys, 'analogChannels'), return; end   % nothing opened yet
        nChannels = numel(data.ephys.analogChannels);   % also without raw data
        % select file
        [file, path] = uigetfile(fullfile(data.defaultPath, '*.csv'), ...
            'Select Channel Mapping File', 'MultiSelect', 'off');
        if isequal(path,0), return; end
        drawnow; figure(fig);
        filename = fullfile(path, file);
        if ~exist(filename, "file"), return; end
        data.rememberPath(filename);
        
        % read channel mapping csv file
        chMapping = readtable(filename);
        % check if channel number is correct.
        if height(chMapping) == nChannels
            % mono-pole recording
        elseif height(chMapping) == 2*nChannels
            % differential recording
            chMapping = chMapping(1:2:end, :);
        else
            error('Channel number mismatch');
        end

        % add analog channel name to the mapping table.
        Analog = data.ephys.analogChannels';
        chMapping = addvars(chMapping, Analog, 'before', 1);

        % add variable names to the sort by dropdown menu
        hd.sortby.Items = chMapping.Properties.VariableNames;
        hd.sortby.Enable = 'on';

        % combine table into channel names
        chMapping = convertvars(chMapping, @isnumeric, @(x)cellstr(num2str(x)));
        chMapping.Names = join(chMapping{:,:}, ', ');        
        data.ephys.chMapping = chMapping;

        % save channel names in the list
        hd.chanList.Items = chMapping.Names;
        
        data.ephys.hd = hd;
        sortChannelMap
    end

    function sortChannelMap()
        hd = data.ephys.hd;
        [~, orders] = sort(data.ephys.chMapping.(hd.sortby.Value));
        hd.chanList.Items = data.ephys.chMapping.Names(orders);
        hd.chanList.ItemsData = orders;
    end

    %% pre-process data
    function preprocess(~,~)
        
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.ephys.hd;

        if ~isfield(hd, 'prepGUI') || ~isgraphics(hd.prepGUI, 'figure')
            hd.prepGUI = ephys.ephys_prep_GUI(mousePos);
            data.ephys.hd = hd;
            updateTypes();   % no deleting while it is open
            notify(data, 'WindowsChanged');
        else
            % if window is already open, don't open another one.
            figure(hd.prepGUI)
        end
    end

    function typeChanged(~,~)
        % a preview belongs to the type it was made from
        if isfield(data.ephys, 'temp'), data.ephys = rmfield(data.ephys, 'temp'); end
        notify(data, 'EphysChanged');   % redraws; the pre-process window follows the type
        updateInfo
    end

    %% sync figures' time and zoom between windows ========
    function axClicked(~,evt)
        data.setTime(evt.IntersectionPoint(1));
    end

    function updateEphysTime(currentTime)
        if data.has('ephys')
            hd = data.ephys.hd;
            hd.timeline.Value = currentTime;
            hd.time.Value = currentTime;
            zoomlim = shared.zoom(data.currentZoom, currentTime, 'pan');
            data.setZoom(zoomlim);
        end
    end

    function zoomIn(~, ~)
        zoomlim = shared.zoom(get(data.ephys.hd.ax, 'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end

    function zoomOut(~, ~)
        zoomlim = shared.zoom(get(data.ephys.hd.ax, 'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end

    function axZoomChanged(src, ~)
        data.setZoom(src.Limits);
    end

    function updateEphysZoom(newZoom)
        hd = data.ephys.hd;
        if data.has('ephys')
            src = currentSource();
            newZoom(1)=max([0 newZoom(1)]);
            newZoom(2)=min([newZoom(2), src.t(end)]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end

    function refresh(~,~)
        if ~data.has('ephys'), return; end
        src = currentSource();
        data.setZoom([0 src.t(end)]);
        ylim(data.ephys.hd.ax, 'auto');   % also undo vertical zoom

        updateInfo();
    end

    function exportAxes(~,~)        
        ax = data.ephys.hd.ax;
        f = figure();
        ax2 = copyobj(ax, f);
        ax2.Units = 'normalized';
        ax2.Position = [0 0 1 1];
    end

    % close function
    function onClose(~,~)
        if ~shared.confirm_close(fig, 'ephys'), return; end
        shared.remember_position('ephys', fig);
        hd = data.ephys.hd;
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
        data.ephys = struct();
        % Clear saved figure handle
        data.fig = rmfield(data.fig, 'ephys');
        delete(fig);  % finally close the GUI
        data.moduleClosed();
    end

end
