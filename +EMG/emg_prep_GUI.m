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

    % line 1 - high pass filter
    chkHighPass = uicheckbox(grid1,'Text', 'High Pass', 'Value', 1);
    editHighPass = uieditfield(grid1, 'numeric','Value',500);
    chkFiltFilt = uicheckbox(grid1, 'Text', 'FiltFilt', 'Value', 0);

    % line 2 - rectify
    chkRectify = uicheckbox(grid1,'Text', 'Rectify', 'Value',1);

    % line 3 - smooth and downsample
    chkDownSample = uicheckbox(grid1,'Text', 'Down Sample', 'Value',1, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 3, 'Column', 1));
    editDownRate = uieditfield(grid1, 'numeric', 'Value', 200);

    % line 4 - buttons: preview, save&close, cancel
    uibutton(grid1, 'Text','Preview', 'ButtonPushedFcn', @preview, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 4, 'Column', 1));
    uibutton(grid1, 'Text','Apply & Close', 'ButtonPushedFcn', @saveClose);
    uibutton(grid1, 'Text','Cancel', 'ButtonPushedFcn', @cancelClose);

    % show the settings of the selected data type: those it was made with
    % (processed), or the defaults (raw)
    defaults = getParameters();
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
        chkHighPass.Value = isfield(p, 'HighPassFreq');
        editHighPass.Value = defaults.HighPassFreq;
        if chkHighPass.Value, editHighPass.Value = p.HighPassFreq; end
        chkFiltFilt.Value = defaults.FiltFilt;
        if isfield(p, 'FiltFilt'), chkFiltFilt.Value = p.FiltFilt; end
        chkRectify.Value = isfield(p, 'Rectify') && p.Rectify;
        chkDownSample.Value = isfield(p, 'DownSampleRate');
        editDownRate.Value = defaults.DownSampleRate;
        if chkDownSample.Value, editDownRate.Value = p.DownSampleRate; end
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
        [processed_data, processed_t, processed_fs] = ...
            EMG.emg_prep(src.data, src.t, parameters, src.sample_rate);
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

        if chkHighPass.Value
            parameters.HighPassFreq = editHighPass.Value;
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
        if isfield(parameters, 'DownSampleRate') && parameters.DownSampleRate > src.sample_rate
            problems{end+1} = sprintf('Down sample %g Hz', parameters.DownSampleRate);
        end
        ok = isempty(problems);
        if ~ok
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

