function fig = sta_GUI(mousePos)
% GAIT.sta_GUI  Step-Triggered Average parameter & history GUI
%
%   fig = GAIT.sta_GUI(mousePos)
%
%   Opens a window near mousePos that lets the user:
%     • Tune STA parameters and compute on demand (Plot button)
%     • Browse a history of runs via a dropdown
%     • Restore parameters + replot any previous run (no recompute)
%     • Delete individual runs or clear all history
%     • Pop the current plot out into a standalone figure
%
%   The window handle is stored at data.gait.hd.sta_GUI and cleared
%   on close so that gait_viewer can use the isfield/isgraphics idiom.

    data = shared.SessionData.instance();

    %% ── Layout constants ─────────────────────────────────────────────────
    WIN_W = 580;
    WIN_H = 480;
    mousePos(2) = mousePos(2) - WIN_H;   % open below cursor (same convention)

    fig = uifigure('Name', 'Step-Triggered Average', ...
        'Position', [mousePos WIN_W WIN_H], ...
        'CloseRequestFcn', @onClose);

    % Root grid: 4 rows × 2 columns
    %   Col 1 (parameters) | Col 2 (Plot button, spans rows 1-2)
    grid1 = uigridlayout(fig, [3 1], ...
        'Padding',      [10 10 10 10], ...
        'RowSpacing',   6, ...
        'ColumnSpacing', 8, ...
        'RowHeight',    {30, '1x', 30});

    %% ── Row 1: max_lag | Control checkbox | Normalize checkbox ───────────
    subR1 = uigridlayout(grid1, [1 6], 'Padding', [0 0 0 0], ...
        'ColumnWidth', {100, '1x', 70,80,80,80}, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 1));

    hd.editMaxLag = uieditfield(subR1, 'numeric', ...
        'Value', 0.5, ...
        'ValueDisplayFormat', 'Max Lag: %.2f s', ...
        'Tooltip', 'Half-window width for STA (seconds)');

    hd.ddMethod = uidropdown(subR1, ...
        'Items',     {'No control', 'Global signal', 'Random time', 'ISI shuffle', 'Dither Offset'}, ...
        'ItemsData', {'none', 'global', 'random_time', 'isi_shuffle', 'dither'}, ...
        'Value',     'dither', ...
        'Tooltip', 'Method of random control', ...
        'ValueChangedFcn', @onMethodChanged);

    hd.editNRep = uieditfield(subR1, 'numeric', ...
        'Value', 100, ...
        'ValueDisplayFormat', 'nRep: %d', ...
        'Tooltip', 'Number of repetitions for random control');

    hd.editOffset = uieditfield(subR1, 'numeric', ...
        'Value', 2, ...
        'ValueDisplayFormat', 'Offset: %.1f s', ...
        'Tooltip', 'Random dither max offset (seconds)');

    hd.chkNormalize = uicheckbox(subR1, ...
        'Text',  'Normalize', ...
        'Value', false, ...
        'Tooltip', 'Plot-time z-score normalization (does not change stored data)');

    % ── Plot button ───────────────────────────
    hd.btnPlot = uibutton(subR1, 'Text', 'Plot', ...
        'FontSize',  14, ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @onPlot);

    %% ── Row 2: plot axes ─────────────────────────────────────────────────
    hd.ax = uiaxes(grid1, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 2, 'Column', 1));
    box(hd.ax, 'off');
    hd.ax.XGrid = 'off';
    hd.ax.YGrid = 'off';
    
    %% ── Row 3: runs dropdown | Delete | Clear All | Pop Out ─────────────
    subR3 = uigridlayout(grid1, [1 4], 'Padding', [0 0 0 0], ...
        'ColumnWidth', {'1x', 40, 40, 40}, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 3, 'Column', 1));

    hd.ddRuns = uidropdown(subR3, ...
        'Items',    {}, ...
        'ItemsData', {}, ...
        'Placeholder', '(no runs yet)', ...
        'ValueChangedFcn', @onRunSelected);

    uibutton(subR3, 'Text', '🗑️', ...
        'ButtonPushedFcn', @onDelete);

    uibutton(subR3, 'Text', '🗑️All', ...
        'ButtonPushedFcn', @onClearAll);

    uibutton(subR3, 'Text', '[➜', ...
        'Tooltip', 'Pop out to new figure', ...
        'ButtonPushedFcn', @onPopOut);

    % rebuild dropdown menu items if there were history data
    rebuildDropdown();
    % Apply initial greying-out rules
    applyGreyOut();

    drawnow
    onRunSelected(hd.ddRuns, []);

    %% ═══════════════════════════════════════════════════════════════════
    %% ── Callbacks ────────────────────────────────────────────────────
    %% ═══════════════════════════════════════════════════════════════════

    function onMethodChanged(~, ~)
        applyGreyOut();
    end

    % ── Main Plot button ──────────────────────────────────────────────────
    function onPlot(~, ~)
        if ~data.has('gait')
            uialert(fig, 'No gait data loaded.', 'Error');
            return;
        end
        if ~data.has('emg')
            uialert(fig, 'No EMG data loaded. Load EMG first.', 'Error');
            return;
        end

        %% Pull live selections from gait_viewer and emg_viewer
        gHd = data.gait.hd;

        % EMG channel & type
        emgType = data.emg.hd.datatype.Value;
        channel = data.emg.hd.chanList.Value;
        if strcmp(emgType, 'Raw')
            emg  = data.emg.analog_data(:, channel);
            emgT = data.emg.t;
        else
            emg  = data.emg.processed.data(:, channel);
            emgT = data.emg.processed.t;
        end

        % Paw / step selection
        pawIdx   = gHd.pawList.Value;
        stepName = gHd.stepList.Value;
        stepIdx  = data.gait.paw(pawIdx).(stepName);
        stepT    = data.gait.t(stepIdx);

        % Channel name for label
        chanItems = data.emg.hd.chanList.Items;
        chanData  = data.emg.hd.chanList.ItemsData;
        if iscell(chanData)
            idx = cellfun(@(x) isequal(x, channel), chanData);
        else
            idx = chanData == channel;
        end
        if any(idx)
            emgChanName = chanItems{find(idx, 1)};
        else
            emgChanName = num2str(channel);
        end

        pawName   = data.gait.paw(pawIdx).name;
        traceName = gHd.trace.Value;

        %% Collect GUI parameters
        max_lag   = hd.editMaxLag.Value;
        method    = hd.ddMethod.Value;
        nRep      = round(hd.editNRep.Value);
        offset    = hd.editOffset.Value;
        normalize = hd.chkNormalize.Value;
        nStd      = 3;   % fixed in spec; could expose later

        %% Compute STA
        result = GAIT.sta(emg, emgT, stepT, ...
            'max_lag',   max_lag, ...
            'method',    method, ...
            'nRep',      nRep, ...
            'offset',    offset, ...
            'normalize', normalize, ...
            'nStd',      nStd, ...
            'plot',      false);

        %% Append caller-supplied metadata fields
        result.pawName     = pawName;
        result.stepName    = stepName;
        result.traceName   = traceName;
        result.emgType     = emgType;
        result.emgChan     = channel;
        result.emgChanName = emgChanName;

        %% Save to data store (grow the array)
        if ~isfield(data.gait, 'sta') || isempty(data.gait.sta)
            data.gait.sta    = result;
            newIdx = 1;
        else
            data.gait.sta(end + 1) = result;
            newIdx = numel(data.gait.sta);
        end

        %% Add entry to dropdown
        label = makeLabel(result);
        currentItems     = hd.ddRuns.Items;
        currentItemsData = hd.ddRuns.ItemsData;
        if isempty(currentItemsData)
            currentItemsData = {};
        end
        hd.ddRuns.Items     = [currentItems, {label}];
        hd.ddRuns.ItemsData = [currentItemsData, {newIdx}];
        hd.ddRuns.Value     = newIdx;

        %% Plot into our axis
        GAIT.plot_sta(result, hd.ax);
        title(hd.ax, label, 'Interpreter', 'none');
    end

    % ── Dropdown selection: restore params & replot ───────────────────────
    function onRunSelected(src, ~)
        if isempty(src.Items)
            return;
        end
        idx    = src.Value;
        result = data.gait.sta(idx);

        % Restore parameter widgets
        hd.editMaxLag.Value  = result.max_lag;
        hd.chkNormalize.Value = result.normalize;
        hd.editNRep.Value    = result.nRep;
        hd.editOffset.Value  = result.offset;

        % Restore method dropdown (use stored method, which may be 'global'
        % even if user originally requested something else — that is correct
        % because result.method reflects what was actually computed)
        if ismember(result.method, hd.ddMethod.ItemsData)
            hd.ddMethod.Value = result.method;
        end

        applyGreyOut();

        % Replot from stored data — no recompute
        GAIT.plot_sta(result, hd.ax);
        title(hd.ax, makeLabel(result), 'Interpreter', 'none');
    end

    % ── Delete current run ────────────────────────────────────────────────
    function onDelete(~, ~)
        if isempty(hd.ddRuns.Items)
            return;
        end
        selIdx = hd.ddRuns.Value;   % run index into data.gait.sta

        % Remove from data store
        keep = true(1, numel(data.gait.sta));
        keep(selIdx) = false;
        data.gait.sta = data.gait.sta(keep);

        % Rebuild dropdown (indices must be renumbered)
        rebuildDropdown();

        % Select adjacent run or blank axis
        n = numel(data.gait.sta);
        if n == 0
            cla(hd.ax);
            title(hd.ax, '');
        else
            newSel = min(selIdx, n);
            hd.ddRuns.Value = newSel;
            onRunSelected(hd.ddRuns, []);
        end
    end

    % ── Clear all runs ────────────────────────────────────────────────────
    function onClearAll(~, ~)
        data.gait.sta       = struct([]);   % empty struct array
        hd.ddRuns.Items     = {};
        hd.ddRuns.ItemsData = {};
        cla(hd.ax);
        title(hd.ax, '');
    end

    % ── Pop out current axis to a new figure ──────────────────────────────
    function onPopOut(~, ~)
        ax  = hd.ax;
        f   = figure();
        ax2 = copyobj(ax, f);
        ax2.Units    = 'normalized';
        ax2.Position = [0 0 1 1];
    end

    % ── Window close ─────────────────────────────────────────────────────
    function onClose(src, ~)
        % Clear the stored handle so gait_viewer knows the window is gone
        if data.has('gait') && isfield(data.gait, 'hd') && isfield(data.gait.hd, 'sta_GUI')
            data.gait.hd = rmfield(data.gait.hd, 'sta_GUI');
        end
        delete(src);
    end

    %% ═══════════════════════════════════════════════════════════════════
    %% ── Helpers ──────────────────────────────────────────────────────
    %% ═══════════════════════════════════════════════════════════════════

    function applyGreyOut()
        method  = hd.ddMethod.Value;
        ctrlOn  = ~strcmp(method, 'none');
        isGlobal = strcmp(method, 'global');

        % Control unchecked → grey everything control-related
        % setEnable(hd.ddMethod,     ctrlOn);
        setEnable(hd.editNRep,     ctrlOn && ~isGlobal);
        setEnable(hd.chkNormalize, ctrlOn);
        setEnable(hd.editOffset,   ctrlOn && strcmp(method, 'dither'));
    end

    function setEnable(widget, tf)
        if tf
            widget.Enable = 'on';
        else
            widget.Enable = 'off';
        end
    end

    function label = makeLabel(result)
        label = [result.pawName ', ' result.stepName ...
                 ' on ' result.traceName ', ' result.emgChanName];
        if result.normalize && ~strcmp(result.method, 'none')
            label = [label ', normalized'];
        end
    end

    function rebuildDropdown()
        if isfield(data.gait, 'sta') && ~isempty(data.gait.sta)
            n = numel(data.gait.sta);
            items     = cell(1, n);
            itemsData = cell(1, n);
            for k = 1:n
                items{k}     = makeLabel(data.gait.sta(k));
                itemsData{k} = k;
            end
            hd.ddRuns.Items     = items;
            hd.ddRuns.ItemsData = itemsData;
        end
    end

end
