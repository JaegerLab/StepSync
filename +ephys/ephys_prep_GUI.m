function fig = ephys_prep_GUI(mousePos)
% pre process window
% The source is the data type selected in the Ephys viewer when Preview or
% Apply is clicked; Apply adds a new processed type.

    data = shared.SessionData.instance();

    %% draw GUI
    % grid 4x3
    mousePos(2)=mousePos(2)-150;
    fig = uifigure('Name', 'Ephys Pre-Process', 'Position', shared.place_window([mousePos 400 150]), ...
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
    typeListener = addlistener(data, 'EphysChanged', @(~,~)showTypeParameters());
    showTypeParameters();
    drawnow

    function showTypeParameters()
        if ~isvalid(fig) || ~data.has('ephys'), return; end
        type = data.ephys.hd.datatype.Value;
        if strcmp(type, lastType), return; end   % e.g. after a preview
        lastType = type;
        parameters = defaults;
        k = sscanf(type, 'Processed %d');
        if ~isempty(k) && k <= numel(data.ephys.processed) && ...
                isstruct(data.ephys.processed(k).parameters) && ...
                ~isempty(data.ephys.processed(k).parameters)
            parameters = data.ephys.processed(k).parameters;
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
        elseif hasHigh && hasLow   % same inference as ephys.ephys_prep
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
        if ~data.has('ephys'), return; end
        src = ephys.ephys_source(data.ephys, data.ephys.hd.datatype.Value);
        ch = data.ephys.hd.chanList.Value(1);

        % only process 1 channel for speed
        parameters = getParameters();
        if ~validFor(src, parameters), return; end
        [newData, newT] = ...
            ephys.ephys_prep(src.data(:,ch), src.t, parameters, src.sampleRate);
        data.ephys.temp.data = newData;
        data.ephys.temp.t = newT;

        notify(data, 'EphysChanged');
    end

    function saveClose(~,~)
        if ~data.has('ephys'), close(fig); return; end
        source = data.ephys.hd.datatype.Value;
        src = ephys.ephys_source(data.ephys, source);
        % process all channels
        parameters = getParameters();
        if ~validFor(src, parameters), return; end
        [processedData, processedT] = ...
            ephys.ephys_prep(src.data, src.t, parameters, src.sampleRate);
        processedFs = src.sampleRate;
        if isfield(parameters, 'DownSampleRate'), processedFs = parameters.DownSampleRate; end
        parameters.Source = source;
        data.ephys.processed(end+1) = struct('data', processedData, 't', processedT, ...
            'sampleRate', processedFs, 'parameters', parameters);

        % show the new type
        types = ephys.ephys_types(data.ephys);
        data.ephys.hd.datatype.Items = types;
        data.ephys.hd.datatype.Value = types{end};

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
        nyquist = src.sampleRate / 2;
        problems = {};
        if isfield(parameters, 'HighPassFreq') && parameters.HighPassFreq >= nyquist
            problems{end+1} = sprintf('High pass %g Hz', parameters.HighPassFreq);
        end
        if isfield(parameters, 'LowPassFreq') && parameters.LowPassFreq >= nyquist
            problems{end+1} = sprintf('Low pass %g Hz', parameters.LowPassFreq);
        end
        if isfield(parameters, 'DownSampleRate') && parameters.DownSampleRate > src.sampleRate
            problems{end+1} = sprintf('Down sample %g Hz', parameters.DownSampleRate);
        end
        ok = isempty(problems);
        if ok && isfield(parameters, 'HighPassFreq') && isfield(parameters, 'LowPassFreq') && ...
                parameters.HighPassFreq == parameters.LowPassFreq
            uialert(fig, 'High and Low must differ for a band filter.', 'Pre-Process');
            ok = false;
        elseif ~ok
            uialert(fig, sprintf('%s: too high for the selected data (%g Hz, Nyquist %g Hz).', ...
                strjoin(problems, ', '), src.sampleRate, nyquist), 'Pre-Process');
        end
    end

    function cancelClose(~,~)
        close(fig);
    end

    function onClose(src,~)
        delete(typeListener);
        if isfield(data.ephys, 'temp')
            data.ephys = rmfield(data.ephys, 'temp');
        end
        delete(src)
        notify(data, 'EphysChanged');   % also re-enables the delete button
        notify(data, 'WindowsChanged');
    end
end

