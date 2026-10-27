function fig = emg_prep_GUI(mousePos)
% pre process window
% The source is the data type selected in the EMG viewer when Preview or
% Apply is clicked; Apply adds a new processed type.

    data = shared.SessionData.instance();

    %% draw GUI
    % grid 4x3
    mousePos(2)=mousePos(2)-150;
    fig = uifigure('Name', 'EMG Pre-Process', 'Position', shared.place_window([mousePos 400 150]), ...
        'CloseRequestFcn', @onClose);
    grid1 = uigridlayout(fig, [4 3]);

    % line 1 - filter, its type and the high pass frequency
    chkFilter = uicheckbox(grid1,'Text', 'Filter', 'Value', 1, ...
        'ValueChangedFcn', @(~,~)updateEnable());
    ddFilterType = uidropdown(grid1, 'Items', {'High pass', 'Low pass', 'Band pass', 'Band stop'}, ...
        'ItemsData', {'highpass', 'lowpass', 'bandpass', 'bandstop'}, 'Value', 'highpass', ...
        'ValueChangedFcn', @(~,~)updateEnable());
    editHighPass = uieditfield(grid1, 'numeric', 'Value', 500, ...
        'ValueDisplayFormat', 'High: %g Hz');

    % line 2 - filtfilt and the low pass frequency
    chkFiltFilt = uicheckbox(grid1, 'Text', 'Filtfilt', 'Value', 0);
    editLowPass = uieditfield(grid1, 'numeric', 'Value', 5000, ...
        'ValueDisplayFormat', 'Low: %g Hz', ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 2, 'Column', 3));

    % line 3 - rectify, smooth and downsample
    chkRectify = uicheckbox(grid1,'Text', 'Rectify', 'Value',1, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 3, 'Column', 1));
    chkDownSample = uicheckbox(grid1,'Text', 'Down Sample', 'Value',1, ...
        'ValueChangedFcn', @(~,~)updateEnable());
    editDownRate = uieditfield(grid1, 'numeric', 'Value', 200, ...
        'ValueDisplayFormat', 'sample rate: %g Hz');

    % line 4 - buttons: preview, save&close, cancel
    uibutton(grid1, 'Text','Preview', 'ButtonPushedFcn', @preview, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 4, 'Column', 1));
    uibutton(grid1, 'Text','Apply & Close', 'ButtonPushedFcn', @saveClose);
    uibutton(grid1, 'Text','Cancel', 'ButtonPushedFcn', @cancelClose);

    % show the settings of the selected data type: those it was made with
    % (processed), or the defaults (raw)
    defaults = getParameters();
    updateEnable();
    lastType = '';
    typeListener = addlistener(data, 'EMGChanged', @(~,~)showTypeParameters());
    showTypeParameters();
    drawnow

    function showTypeParameters()
        if ~isvalid(fig) || ~data.has('emg'), return; end
        type = data.emg.hd.datatype.Value;
        if strcmp(type, lastType), return; end   % e.g. after a preview
        lastType = type;
        parameters = defaults;
        k = sscanf(type, 'Processed %d');
        if ~isempty(k) && k <= numel(data.emg.processed) && ...
                isstruct(data.emg.processed(k).parameters) && ...
                ~isempty(data.emg.processed(k).parameters)
            parameters = data.emg.processed(k).parameters;
        end
        setParameters(parameters);
    end

    % inverse of getParameters; missing values keep the defaults
    function setParameters(p)
        hasHigh = isfield(p, 'HighPassFreq');
        hasLow = isfield(p, 'LowPassFreq');
        chkFilter.Value = isfield(p, 'FilterType') || hasHigh || hasLow;
        if isfield(p, 'FilterType')
            ddFilterType.Value = p.FilterType;
        elseif hasHigh && hasLow   % same inference as EMG.emg_prep
            ddFilterType.Value = 'bandpass';
        elseif hasLow
            ddFilterType.Value = 'lowpass';
        else
            ddFilterType.Value = 'highpass';
        end
        editHighPass.Value = defaults.HighPassFreq;
        if hasHigh, editHighPass.Value = p.HighPassFreq; end
        editLowPass.Value = defaults.LowPassFreq;
        if hasLow, editLowPass.Value = p.LowPassFreq; end
        chkFiltFilt.Value = defaults.FiltFilt;
        if isfield(p, 'FiltFilt'), chkFiltFilt.Value = p.FiltFilt; end
        chkRectify.Value = isfield(p, 'Rectify') && p.Rectify;
        chkDownSample.Value = isfield(p, 'DownSampleRate');
        editDownRate.Value = defaults.DownSampleRate;
        if chkDownSample.Value, editDownRate.Value = p.DownSampleRate; end
        updateEnable();
    end

    % filter settings only with Filter on, and only the frequencies the
    % filter type uses
    function updateEnable()
        on = chkFilter.Value;
        type = ddFilterType.Value;
        ddFilterType.Enable = on;
        chkFiltFilt.Enable = on;
        editHighPass.Enable = on && ~strcmp(type, 'lowpass');
        editLowPass.Enable = on && ~strcmp(type, 'highpass');
        editDownRate.Enable = chkDownSample.Value;
    end

    function preview(~,~)
        if ~data.has('emg'), return; end
        src = EMG.emg_source(data.emg, data.emg.hd.datatype.Value);
        ch = data.emg.hd.chanList.Value(1);

        % only process 1 channel for speed
        parameters = getParameters();
        if ~validFor(src, parameters), return; end
        [new_data, new_t] = ...
            EMG.emg_prep(src.data(:,ch), src.t, parameters, src.sample_rate);
        data.emg.temp.data = new_data;
        data.emg.temp.t = new_t;

        notify(data, 'EMGChanged');
    end

    function saveClose(~,~)
        if ~data.has('emg'), close(fig); return; end
        source = data.emg.hd.datatype.Value;
        src = EMG.emg_source(data.emg, source);
        % process all channels
        parameters = getParameters();
        if ~validFor(src, parameters), return; end
        [processed_data, processed_t] = ...
            EMG.emg_prep(src.data, src.t, parameters, src.sample_rate);
        processed_fs = src.sample_rate;
        if isfield(parameters, 'DownSampleRate'), processed_fs = parameters.DownSampleRate; end
        parameters.Source = source;
        data.emg.processed(end+1) = struct('data', processed_data, 't', processed_t, ...
            'sample_rate', processed_fs, 'parameters', parameters);

        % show the new type
        types = EMG.emg_types(data.emg);
        data.emg.hd.datatype.Items = types;
        data.emg.hd.datatype.Value = types{end};

        close(fig);
    end

    function parameters = getParameters()
        % save parameters
        parameters = struct();

        if chkFilter.Value
            parameters.FilterType = ddFilterType.Value;
            if editHighPass.Enable
                parameters.HighPassFreq = editHighPass.Value;
            end
            if editLowPass.Enable
                parameters.LowPassFreq = editLowPass.Value;
            end
            parameters.FiltFilt = chkFiltFilt.Value;
        end
        parameters.Rectify = chkRectify.Value;
        if chkDownSample.Value
            parameters.DownSampleRate = editDownRate.Value;
        end
    end

    % Frequencies must fit the source's rate (processed data may be slow).
    function ok = validFor(src, parameters)
        nyquist = src.sample_rate / 2;
        problems = {};
        if isfield(parameters, 'HighPassFreq') && parameters.HighPassFreq >= nyquist
            problems{end+1} = sprintf('High pass %g Hz', parameters.HighPassFreq);
        end
        if isfield(parameters, 'LowPassFreq') && parameters.LowPassFreq >= nyquist
            problems{end+1} = sprintf('Low pass %g Hz', parameters.LowPassFreq);
        end
        if isfield(parameters, 'DownSampleRate') && parameters.DownSampleRate > src.sample_rate
            problems{end+1} = sprintf('Down sample %g Hz', parameters.DownSampleRate);
        end
        ok = isempty(problems);
        if ok && isfield(parameters, 'HighPassFreq') && isfield(parameters, 'LowPassFreq') && ...
                parameters.HighPassFreq == parameters.LowPassFreq
            uialert(fig, 'High and Low must differ for a band filter.', 'Pre-Process');
            ok = false;
        elseif ~ok
            uialert(fig, sprintf('%s: too high for the selected data (%g Hz, Nyquist %g Hz).', ...
                strjoin(problems, ', '), src.sample_rate, nyquist), 'Pre-Process');
        end
    end

    function cancelClose(~,~)
        close(fig);
    end

    function onClose(src,~)
        delete(typeListener);
        if isfield(data.emg, 'temp')
            data.emg = rmfield(data.emg, 'temp');
        end
        delete(src)
        notify(data, 'EMGChanged');   % also re-enables the delete button
        notify(data, 'WindowsChanged');
    end
end

