function fig = dlc_viewer()
    data = shared.SessionData.instance();

    drawGUI();

    function drawGUI()
        % DLC viewer window with uigridlayout
        fig = uifigure('Name', 'DLC Viewer', 'Position', [100 100 1000 500], ...
            'CloseRequestFcn', @onClose);
        data.fig(1).dlc = fig;
        shared.MenuBar(fig, {'Open', @openDLC; 'Save', @saveDLC});
        drawnow
        grid1 = uigridlayout(fig, [3 2]);
        grid1.Padding = [20,20,20,20];
        grid1.ColumnWidth = {'1x', 140};
        grid1.RowHeight = {30, '1x', 30};

        hd = struct();

        %% Row 1: DLC processing
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0], ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 1));
        subgrid1.ColumnWidth = {'1x', 30, 30, 30, 150, 100};
            hd.info = uilabel(subgrid1,'Text',' Info:', 'BackgroundColor','w');
            hd.chk_x = uicheckbox(subgrid1,'Text','X','Value',1, ...
                'ValueChangedFcn', @checkXChanged);
            hd.chk_y = uicheckbox(subgrid1,'Text','Y','Value',1, ...
                'ValueChangedFcn', @checkYChanged);
            hd.chk_p = uicheckbox(subgrid1,'Text','P','Value',0, ...
                'ValueChangedFcn', @checkPChanged);
            hd.frameRate = shared.frame_rate_field(subgrid1);
            hd.currentFrame = uieditfield(subgrid1,'numeric','Value',1, ...
                'ValueDisplayFormat','Frame: %d');
            
        % subgrid3 = uigridlayout(grid1, [1 2], 'Padding', [0 0 0 0]);
        % subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
        uibutton(grid1,'Text','DLC Fix', 'ButtonPushedFcn',@openFix, ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));
            % hd.manualFix = uicheckbox(subgrid3,'Text','Man. Fix','Value', 0, ...
            %     'ValueChangedFcn',@manualFix);


        %% Row 2: DLC plot
        hd.ax = uiaxes(grid1);
        hd.ax.Layout.Row = [2 3]; hd.ax.Layout.Column = 1;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        axis(hd.ax, 'ij'); 
        xlabel(hd.ax, 'Frame'); ylabel(hd.ax, 'Location (pixel)');
        disableDefaultInteractivity(hd.ax);

        hold(hd.ax, 'on');
        hd.ax.ButtonDownFcn = @axClicked;   % clicks on blank space

        subgrid3 = uigridlayout(grid1, [2 1], 'Padding', [0 0 0 0], ...
            'RowHeight', {'1x', 30});
        subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
            hd.list_bodyparts = uilistbox(subgrid3, 'Multiselect', 'off', ...
                'Enable','off', 'ValueChangedFcn', @(src,evt)listChanged());
            hd.deleteBodypart = uibutton(subgrid3, 'Text', 'Delete bodypart', ...
                'Enable', 'off', 'ButtonPushedFcn', @deleteBodypart);

        %% Row 3:  zoom in, zoom out, update buttons
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
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateDLCtime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateDLCzoom(src.currentZoom));
        hd.dlcListener = addlistener(data, 'DLCChanged', @(src, evt)showBodypart());
        hd.gaitListener = addlistener(data, 'GaitChanged', @(src, evt)drawSteps());
        hd.infoListener = addlistener(data, 'InfoChanged', @(src, evt)updateInfo());

        data.dlc(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    function openDLC(~,~)
        hd = data.dlc.hd;
        [filename, pathname]=uigetfile(fullfile(data.defaultPath, '*.csv'), 'Open DeepLabCut file');
        drawnow; figure(fig);
        if isequal(pathname,0), return; end
        filename=fullfile(pathname, filename);
        if ~exist(filename, "file"), return; end
        data.rememberPath(filename);

        % This reading function handles different kinds of data formats
        tabledlc = DLC.align_to_video(DLC.read_dlc(filename), fig);
        data.dlc.table = tabledlc;
        data.dlc.filename = filename;      % shown in the title; the last saved file
        data.dlc.source_file = filename;   % Save may not overwrite it
        data.dlc.seg = [];
        data.dlc.seg_bodypart = '';

        % update body part list
        hd.list_bodyparts.Enable = 'on';
        hd.list_bodyparts.Items = tabledlc.Properties.UserData;
        hd.deleteBodypart.Enable = 'on';

        % axis(hd.ax,'tight');
        % ylim(hd.ax, [0 1200]);
        % xlim(hd.ax, [1 height(tabledlc)]);

        data.dlc.hd = hd;

        % update frame rate and total frames
        notify(data, 'InfoChanged')
        % draw time line first: it stays below the traces, so clicks reach them
        updateDLCtime(data.currentTime);
        % draw trajectory plot
        data.notifyDLC('open', tabledlc.Properties.UserData);
    end

    % Save committed body parts as a DLC csv; uncommitted fix previews
    % (temp_*) are left out by DLC.save_csv.
    function saveDLC(~,~)
        if ~data.has('dlc')
            uialert(fig, 'There is no DLC data to save.', 'Save');
            return;
        end
        [range, ok] = shared.ask_save_range(fig, 'DLC');
        if ~ok, return; end
        original = data.dlc.filename;
        if isfield(data.dlc, 'source_file'), original = data.dlc.source_file; end
        [folder, base] = fileparts(original);
        if ~isempty(data.defaultPath), folder = data.defaultPath; end
        [file, path] = uiputfile('*.csv', 'Save DLC', fullfile(folder, [base '_StepSync.csv']));
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        if strcmpi(filename, original)
            uialert(fig, sprintf('%s is the file this DLC data was opened from. Choose another name.', file), ...
                'Save refused');
            return;
        end
        tabledlc = data.dlc.table;
        if ~isempty(range)
            tabledlc = DLC.crop_table(tabledlc, data.dlc.t, range);
            if height(tabledlc) == 0
                uialert(fig, 'No frames lie in the zoom window.', 'Save');
                return;
            end
        end
        DLC.save_csv(filename, tabledlc);
        data.rememberPath(filename);
        data.dlc.filename = filename;   % the title shows the saved file
        fig.Name = ['DLC Viewer: ' filename];
    end

    function listChanged()
        data.notifyDLC('selection');
    end

    % Delete the selected body part from the table (and its fix preview).
    function deleteBodypart(~,~)
        if ~data.has('dlc'), return; end
        hd = data.dlc.hd;
        bodypart = hd.list_bodyparts.Value;
        items = hd.list_bodyparts.Items;
        if numel(items) < 2
            uialert(fig, 'The only body part cannot be deleted.', 'Delete bodypart');
            return;
        end
        answer = uiconfirm(fig, sprintf('Delete %s?', bodypart), 'Delete bodypart', ...
            'Options', {'Delete', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
            'Icon', 'warning', 'Interpreter', 'none');
        if ~strcmp(answer, 'Delete'), return; end

        if isfield(data.dlc, 'seg_bodypart') && strcmp(data.dlc.seg_bodypart, bodypart)
            temp = intersect({'temp_x', 'temp_y', 'temp_likelihood'}, ...
                data.dlc.table.Properties.VariableNames);
            data.dlc.table = removevars(data.dlc.table, temp);
            data.dlc.seg = [];
            data.dlc.seg_bodypart = '';
        end
        cols = intersect(strcat(bodypart, {'_x', '_y', '_likelihood'}), ...
            data.dlc.table.Properties.VariableNames);
        data.dlc.table = removevars(data.dlc.table, cols);
        names = data.dlc.table.Properties.UserData;
        data.dlc.table.Properties.UserData = names(~strcmp(names, bodypart));

        idx = find(strcmp(items, bodypart));
        items(idx) = [];
        hd.list_bodyparts.Items = items;
        hd.list_bodyparts.Value = items{min(idx, end)};
        data.notifyDLC('delete', {bodypart});
    end

    % main update function.=========================
    function showBodypart()
        if ~data.has('dlc'); return; end

        hd = data.dlc.hd;
        S = DLC.fix_style();
        
        bodypart = hd.list_bodyparts.Value;

        % update dlc plots
        tabledlc = data.dlc.table;
        t = data.dlc.t(:);
        xdata = tabledlc.([bodypart '_x']);
        ydata = tabledlc.([bodypart '_y']);
        if ismember([bodypart '_likelihood'], tabledlc.Properties.VariableNames)
            pdata = tabledlc.([bodypart '_likelihood']);
        else
            pdata = nan(size(xdata));
        end

        % update info text
        f = hd.currentFrame.Value;
        hd.info.Text = sprintf( ...
            ['total frames: %d, total time: %.2f\n' ...
            'x=%g, y=%g, p=%.3g'], ...
            length(xdata), max(data.dlc.t, [], 'omitnan'), ...
            xdata(f), ydata(f), pdata(f));

        % plot xy plots
        hold(hd.ax, "on");
        % The time line must exist before the traces are created: plot order
        % keeps it below them (no uistack: it fails with yyaxis). Session
        % load draws the traces before TimeChanged, so create it here.
        if ~isfield(hd, 'timeline_dlc') || ~ishghandle(hd.timeline_dlc)
            hd = drawTimeline(hd);
        end
        hd = shared.myPlot(@plot, hd, 'xplot', hd.ax, t, xdata, ...
                '-', 'Color', S.xColor, 'LineWidth', S.trace, ...
                'HitTest', 'on', 'ButtonDownFcn', @axClicked, 'DisplayName', S.legend.x, ...
                'Visible', hd.chk_x.Value);

        hd = shared.myPlot(@plot, hd, 'yplot', hd.ax, t, ydata, ...
                '-', 'Color', S.yColor, 'LineWidth', S.trace, ...
                'HitTest', 'on', 'ButtonDownFcn', @axClicked, 'DisplayName', S.legend.y, ...
                'Visible', hd.chk_y.Value);

        set([hd.xplot hd.yplot], 'HitTest', 'on', 'ButtonDownFcn', @axClicked);

        % likelihood on the right y axis
        yyaxis(hd.ax, 'right');
        hd = shared.myPlot(@plot, hd, 'pplot', hd.ax, t, pdata, ...
                '-', 'Color', S.pColor, 'LineWidth', S.trace, ...
                'HitTest', 'off', 'DisplayName', S.legend.p);
        hd.pplot.Visible = hd.chk_p.Value;    % myPlot only sets this on creation
        ylim(hd.ax, [0 1]);                   % ylim([0 1]) alone targets gca, not hd.ax
        hd.ax.YAxis(2).Color = S.pColor;
        hd.ax.YAxis(2).Visible = hd.chk_p.Value;

        yyaxis(hd.ax, 'left')
        hd.ax.YAxis(1).Color = S.leftAxisColor;   % yyaxis recolours the left axis

        % fix overlay: only for the body part the segments belong to
        seg = currentSeg(bodypart);
        if isempty(seg)
            hd = setFixVisible(hd, '_x', false);
            hd = setFixVisible(hd, '_y', false);
        else
            hd = drawFix(hd, '_x', t, xdata, tabledlc.temp_x, seg, S);
            hd = drawFix(hd, '_y', t, ydata, tabledlc.temp_y, seg, S);
            hd = setFixVisible(hd, '_x', hd.chk_x.Value);
            hd = setFixVisible(hd, '_y', hd.chk_y.Value);

            % % layer order: interpolation behind the trace; jumps, frame
            % % markers and attention circles on top (in that order)
            % uistack([hd.fix_interp_x hd.fix_interp_y], 'bottom');
            % uistack([hd.xplot hd.yplot], 'top');
            % for name = {'jump', 'unflag', 'quest', 'good', 'userGood', 'bad', ...
            %             'userBad', 'attnInterp', 'attnLongBad', 'attnConflict'}
            %     uistack([hd.(['fix_' name{1} '_x']) hd.(['fix_' name{1} '_y'])], 'top');
            % end
            % if isfield(hd, 'timeline_dlc') && ishghandle(hd.timeline_dlc)
            %     uistack(hd.timeline_dlc, 'bottom');
            % end
        end
        data.dlc.hd = hd;
        updateLegend(hd);
        drawSteps();
    end

    % gait steps on the X and Y traces (left axis), following the X/Y checkboxes
    function drawSteps()
        if ~isfield(data.dlc, 'hd'), return; end
        hd = data.dlc.hd;
        steps = GAIT.current_steps(data);
        if data.has('dlc') && ~isempty(steps) && ~isempty(steps.t)
            if numel(hd.ax.YAxis) > 1, yyaxis(hd.ax, 'left'); end
            spec = {'Marker', 'o', 'MarkerEdgeColor', 'm', 'LineWidth', 2, ...
                'HitTest', 'off', 'HandleVisibility', 'off'};
            hd = shared.myPlot(@scatter, hd, 'stepX', hd.ax, steps.t, steps.x, spec{:});
            hd = shared.myPlot(@scatter, hd, 'stepY', hd.ax, steps.t, steps.y, spec{:});
            hd.stepX.Visible = hd.chk_x.Value;
            hd.stepY.Visible = hd.chk_y.Value;
        else
            for field = {'stepX', 'stepY'}
                if isfield(hd, field{1}) && isgraphics(hd.(field{1}))
                    hd.(field{1}).Visible = 'off';
                end
            end
        end
        data.dlc.hd = hd;
    end

    % One legend entry per item. Fix layers exist twice (x and y copies with
    % the same DisplayName): use the x copy, or the y copy when x is hidden.
    % Hidden or empty layers are left out.
    function updateLegend(hd)
        S = DLC.fix_style();
        h = gobjects(0);
        for f = {'xplot', 'yplot', 'pplot'}
            if isfield(hd, f{1}) && isgraphics(hd.(f{1})) && isOn(hd.(f{1}))
                h(end+1) = hd.(f{1}); %#ok<AGROW>
            end
        end
        for name = S.legendOrder
            for sfx = {'_x', '_y'}
                fld = ['fix_' name{1} sfx{1}];
                if isfield(hd, fld) && isgraphics(hd.(fld)) && isOn(hd.(fld)) && ...
                        any(~isnan(hd.(fld).YData))
                    h(end+1) = hd.(fld); %#ok<AGROW>
                    break;
                end
            end
        end
        if isempty(h)
            legend(hd.ax, 'off');
        else
            % AutoUpdate off: objects added later (e.g. gait markers) stay out
            legend(hd.ax, h, 'AutoUpdate', 'off', 'Location', S.legendLocation);
        end
    end

    % draw all fix layers for one coordinate (suffix '_x' or '_y')
    function hd = drawFix(hd, sfx, t, v, vfix, seg, S)
        fe   = repelem(seg.flag, seg.len);          % flag per frame
        win  = seg.win_width;
        good = fe > 0;
        clickable = {'ButtonDownFcn', @axClicked};
        unclickable = {'HitTest', 'off'};
        % markers sit on the trace: let clicks fall through to it
        passThru  = {'PickableParts', 'none', 'LineStyle', 'none'};
        mk   = [{'MarkerSize', S.markSize, 'LineWidth', S.markWidth}, passThru];
        attn = [{'Marker', S.attnMarker, 'MarkerSize', S.attnSize, 'LineWidth', S.attnWidth}, passThru];

        % interpolation where it replaces data, joined to the good frames
        show = ~good;
        show = show | [show(2:end); false] | [false; show(1:end-1)];
        Y = vfix(:); Y(~show) = NaN;
        hd = shared.myPlot(@plot, hd, ['fix_interp' sfx], hd.ax, t, Y, ...
            S.interpStyle, 'Color', S.interpColor, 'LineWidth', S.interpWidth, unclickable{:}, ...
            'DisplayName', S.legend.interp);

        % jumps (all, including conflicts): thin dashed, on top of the trace
        [X, Y] = jumpXY(t, v, seg, true(numel(seg.start) - 1, 1));
        hd = shared.myPlot(@plot, hd, ['fix_jump' sfx], hd.ax, nonEmpty(X), nonEmpty(Y), ...
            S.jumpStyle, 'Color', S.jumpColor, 'LineWidth', S.jumpWidth, clickable{:}, ...
            'DisplayName', S.legend.jump);

        % frame markers (seeds from the algorithm are not marked)
        userGood = repelem(seg.flag == 2 & ~(seg.len >= win), seg.len);  % seed it would not have made
        layers = { ...
            'good',     fe == 1,  S.goodMarker,     S.good, 'none'; ...
            'userGood', userGood, S.userGoodMarker, S.good, S.good; ...
            'bad',      fe == -1, S.badMarker,      S.bad,  'none'; ...
            'quest',    fe == -2, S.questMarker,    S.grey, 'none'; ...
            'userBad',   fe == -3, S.userBadMarker,   S.bad,  'none'; ...
            'unflag',   fe == 0,  S.unflagMarker,   S.grey, 'none'};
        for i = 1:size(layers, 1)
            sel = layers{i, 2};
            hd = shared.myPlot(@plot, hd, ['fix_' layers{i, 1} sfx], hd.ax, ...
                nonEmpty(t(sel)), nonEmpty(v(sel)), layers{i, 3}, ...
                'Color', layers{i, 4}, 'MarkerFaceColor', layers{i, 5}, mk{:}, ...
                'DisplayName', S.legend.(layers{i,1}));
        end

        % --- needs attention: large circles at both ends --------------------
        % neighbouring good segments: the two frames of the jump between them
        a = seg.stop([seg.conflict(:); false]);
        f = [a; a + 1];
        hd = shared.myPlot(@plot, hd, ['fix_attnConflict' sfx], hd.ax, ...
            nonEmpty(t(f)), nonEmpty(v(f)), 'Color', S.attnConflict, attn{:}, ...
            'DisplayName', S.legend.attnConflict);
        % long segments the algorithm flagged bad (likely mis-flagged)
        k = find((seg.flag == -1 | seg.flag == -2) & seg.len >= S.longBadFrac * win);
        f = [seg.start(k); seg.stop(k)];
        hd = shared.myPlot(@plot, hd, ['fix_attnLongBad' sfx], hd.ax, ...
            nonEmpty(t(f)), nonEmpty(v(f)), 'Color', S.attnLongBad, attn{:}, ...
            'DisplayName', S.legend.attnLongBad);
        % long interpolation with no good frame inside: ends of the stretch
        d = diff([false; ~good; false]);
        rs = find(d == 1); re = find(d == -1) - 1;
        long = (re - rs + 1) >= S.longInterpFrac * win;
        f = [rs(long); re(long)];
        hd = shared.myPlot(@plot, hd, ['fix_attnInterp' sfx], hd.ax, ...
            nonEmpty(t(f)), nonEmpty(vfix(f)), 'Color', S.attnInterp, attn{:}, ...
            'DisplayName', S.legend.attnInterp);
    end

    % show/hide all fix layers of one coordinate
    function hd = setFixVisible(hd, sfx, true_false)
        f = fieldnames(hd);
        f = f(strncmp(f, 'fix_', 4) & endsWith(f, sfx));
        for i = 1:numel(f)
            if ishghandle(hd.(f{i}))
                hd.(f{i}).Visible = true_false;
            end
        end
    end

    % segment structure of the current fix, if it belongs to this body part
    function seg = currentSeg(bodypart)
        seg = [];
        if ~data.has('dlc') || ~isfield(data.dlc, 'seg') || isempty(data.dlc.seg)
            return;
        end
        if ~isfield(data.dlc, 'seg_bodypart') || ~strcmp(data.dlc.seg_bodypart, bodypart)
            return;
        end
        if ~ismember('temp_x', data.dlc.table.Properties.VariableNames) || ...
                data.dlc.seg.n_frames ~= height(data.dlc.table)
            return;
        end
        seg = data.dlc.seg;
    end

    % checkbox callback
    function checkXChanged(src,~)
        hd = data.dlc.hd;
        if isfield(hd, 'xplot') && ishghandle(hd.xplot)
            hd.xplot.Visible = src.Value;
        end
        has_fix = ~isempty(currentSeg(hd.list_bodyparts.Value));
        hd = setFixVisible(hd, '_x', src.Value && has_fix);
        data.dlc.hd = hd;
        updateLegend(hd);
        drawSteps();
    end
    function checkYChanged(src,~)
        hd = data.dlc.hd;
        if isfield(hd, 'yplot') && ishghandle(hd.yplot)
            hd.yplot.Visible = src.Value;
        end
        has_fix = ~isempty(currentSeg(hd.list_bodyparts.Value));
        hd = setFixVisible(hd, '_y', src.Value && has_fix);
        data.dlc.hd = hd;
        updateLegend(hd);
        drawSteps();
    end

    function checkPChanged(src,~)
        hd = data.dlc.hd;
        if isfield(hd, 'pplot') && ishghandle(hd.pplot)
            hd.pplot.Visible = src.Value;
            hd.ax.YAxis(2).Visible = src.Value;
            updateLegend(hd);
        end
    end

    function updateFrameRate(frameRate)
        hd = data.dlc.hd;
        totalFrame = height(data.dlc.table);
        data.dlc.t = data.getFrameTimes(totalFrame);

        showBodypart();            % redraw trace and fix layers on new time base

        % update xlims if it's out of bound
        xlims = xlim(hd.ax);
        xlims = [max(xlims(1), data.dlc.t(1)) min(xlims(2), max(data.dlc.t, [], 'omitnan'))];
        if xlims(2) > xlims(1), xlim(hd.ax, xlims); end
        
        if frameRate == 1
            xlabel(hd.ax, 'Frame')
        else
            xlabel(hd.ax, 'Time (s)')
        end
    end

    % triggered by info event
    function updateInfo()
        if ~data.has('dlc'), return; end
        hd = data.dlc.hd;
        if isfield(data.dlc, 'filename')
            fig.Name = ['DLC Viewer: ' data.dlc.filename];
        end

        % collect info
        frameRate = data.getFrameRate();
        totalFrame = height(data.dlc.table);
        data.dlc.t = data.getFrameTimes(totalFrame);

        currentFrame = shared.time_to_frame(data.dlc.t, data.currentTime);
        currentFrame = min(totalFrame, max(1, currentFrame));
        hd.currentFrame.Value = currentFrame;

        updateFrameRate(frameRate);
    end

    function openFix(~,~)
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.dlc.hd;
        if ~isfield(hd, 'fixGUI') || ~isgraphics(hd.fixGUI, 'figure')
            % open a new window
            hd.fixGUI = DLC.dlc_fix_GUI(mousePos);
            data.dlc.hd = hd;
            notify(data, 'WindowsChanged');
        else
            % if window is already open, activate it.
            figure(hd.fixGUI)
        end
    end

    % === sync time and zoom ===========
    % click (anywhere): set time
    % ctrl-click on a line:  add / remove the jump between the two frames
    % shift-click on a line: toggle the segment good (seed) / bad (userBad)
    function axClicked(src,evt)
        clickType = get(fig, 'SelectionType');

        if isequal(clickType, "normal")
            % direct click, change time.
            data.setTime(evt.IntersectionPoint(1));
            return;
        end
        % edits only when a plotted line was hit, not blank space
        if ~(isprop(src, 'Type') && strcmp(src.Type, 'line')), return; end

        hd = data.dlc.hd;
        % the P trace is for reference only: no edits from it
        if isfield(hd, 'pplot') && isequal(src, hd.pplot), return; end
        bodypart = hd.list_bodyparts.Value;
        seg = currentSeg(bodypart);
        if isempty(seg), return; end        % no fix preview for this body part

        t  = data.dlc.t(:);
        tc = evt.IntersectionPoint(1);
        if isequal(clickType, "alt")
            % ctrl-click: toggle jump
            seg = DLC.dlc_seg_toggle_jump(seg, jumpAtClick(src, tc, t, seg, hd));
        elseif isequal(clickType, "extend")
            % shift-click: toggle segment, userBad until changed again
            [~, f] = min(abs(t - tc));
            k = find(seg.start <= f & seg.stop >= f, 1);
            if seg.flag(k) > 0
                seg.flag(k) = -3;
            else
                seg.flag(k) = 2;
            end
            seg.is_new(k) = true;
        else
            return;                         % e.g. double-click
        end

        % recheck only around the edit
        xdata = data.dlc.table.([bodypart '_x']);
        ydata = data.dlc.table.([bodypart '_y']);
        [tempX, tempY, mask, seg] = DLC.dlc_fix(xdata, ydata, [], [], seg);

        data.dlc.table.temp_x = tempX;
        data.dlc.table.temp_y = tempY;
        data.dlc.table.temp_likelihood = DLC.seg_likelihood(seg);
        data.dlc.seg = seg;
        data.notifyDLC('preview');
    end

    % frame at such that the clicked jump lies between frames a and a+1
    function a = jumpAtClick(src, tc, t, seg, hd)
        S = DLC.fix_style();
        isJumpLine = isprop(src, 'Tag') && startsWith(src.Tag, 'fix_jump');
        xl = xlim(hd.ax);
        tol = S.snapPx * diff(xl) / max(1, hd.ax.InnerPosition(3));
        a = snapJump(tc, t, seg.stop(1:end-1), tol, isJumpLine);
    end

    function updateDLCtime(currentTime)
        if data.has('dlc')
            hd = data.dlc.hd;
            currentFrame = shared.time_to_frame(data.dlc.t, currentTime);
            hd.currentFrame.Value = currentFrame;

            % update info text
            bodypart = hd.list_bodyparts.Value;
            tabledlc = data.dlc.table;
            xdata = tabledlc.([bodypart '_x']);
            ydata = tabledlc.([bodypart '_y']);
            if ismember([bodypart '_likelihood'], tabledlc.Properties.VariableNames)
                pdata = tabledlc.([bodypart '_likelihood']);
            else
                pdata = nan(size(xdata));
            end
            f = hd.currentFrame.Value;
            hd.info.Text = sprintf( ...
                ['total frames: %d, total time: %.2f\n' ...
                'x=%g, y=%g, p=%.3g'], ...
                length(xdata), max(data.dlc.t, [], 'omitnan'), ...
                xdata(f), ydata(f), pdata(f));

            hd = drawTimeline(hd);
            data.dlc.hd = hd;

            data.setTime(currentTime);
    
            % if time is out of current lims, move the zoom frame over.
            zoomlim = shared.zoom(get(hd.ax,'xLim'), currentTime, 'pan');
            data.setZoom(zoomlim);
        end
    end

    % time line on the left side (see drawP)
    function hd = drawTimeline(hd)
        if numel(hd.ax.YAxis) > 1, yyaxis(hd.ax, 'left'); end
        hd = shared.myPlot(@xline, hd, 'timeline_dlc', hd.ax, ...
            data.currentTime,  'k', ...
            'HitTest', 'off', 'HandleVisibility', 'off');
    end

    function zoomIn(~, ~)
        zoomlim = shared.zoom(get(data.dlc.hd.ax,'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end

    function zoomOut(~, ~)
        zoomlim = shared.zoom(get(data.dlc.hd.ax,'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end

    % callback function for axis zoom change
    function axZoomChanged(src,~)
        data.setZoom(src.Limits);
    end

    % response function for zoomChanged listener
    function updateDLCzoom(newZoom)
        if data.has('dlc')
            newZoom(1) = max([0 newZoom(1)]);
            newZoom(2) = min([newZoom(2) max(data.dlc.t, [], 'omitnan')]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(data.dlc.hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end

    function refresh(~,~)
        if ~data.has('dlc'), return; end
        finiteTime = data.dlc.t(isfinite(data.dlc.t));
        if numel(finiteTime)>1, data.setZoom(finiteTime([1 end])); end
        ylim(data.dlc.hd.ax, 'auto');   % also undo vertical zoom

        updateInfo();
    end

    function exportAxes(~,~)        
        ax = data.dlc.hd.ax;
        f = figure();
        ax2 = copyobj(ax, f);
        ax2.Units = 'normalized';
        ax2.Position = [0 0 1 1];
    end

    % close function =================================
    function onClose(src,~)
        if ~shared.confirm_close(fig, 'DLC Viewer'), return; end
        hd=data.dlc.hd;
        % close fix GUI first.
        if isfield(hd, 'fixGUI') && isgraphics(hd.fixGUI)
            close(hd.fixGUI)
        end
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
        data.dlc = struct();
        % Clear saved figure handle
        data.fig = rmfield(data.fig, 'dlc');
        data.notifyDLC('close');   % e.g. the video viewer hides its DLC markers
        delete(src);  % finally close the GUI
        data.moduleClosed();
    end
end

% ==========================================================================
% local helpers (no shared state)
% ==========================================================================
function tf = isOn(h)
% Visible is 'on'/'off' or an OnOffSwitchState depending on MATLAB version
tf = strcmp(char(h.Visible), 'on');
end

function v = nonEmpty(v)
% plot() needs at least one point to return a line handle; NaN draws nothing.
if isempty(v), v = NaN; end
end

% function [X, Y] = segXY(t, v, seg, sel)
% % Points of the selected segments, NaN-separated so that neighbouring
% % segments are never joined across a jump.
% k = find(sel);
% n = sum(seg.len(k)) + numel(k);
% X = nan(n, 1); Y = X;
% p = 1;
% for i = k'
%     r = seg.start(i):seg.stop(i);
%     m = numel(r);
%     X(p:p+m-1) = t(r);
%     Y(p:p+m-1) = v(r);
%     p = p + m + 1;
% end
% end

function [X, Y] = jumpXY(t, v, seg, sel)
% Line pieces from the last frame before each selected jump to the first
% frame after it, NaN-separated.
a = seg.stop([sel(:); false]);          % jump k lies after frame seg.stop(k)
X = [t(a) t(a+1) nan(numel(a), 1)]';
Y = [v(a) v(a+1) nan(numel(a), 1)]';
X = X(:); Y = Y(:);
end

function a = snapJump(tc, t, J, tol, forceSnap)
% Frame interval under the click (jump after frame a), snapped to an
% existing jump J if one lies within tol (or the jump line itself was hit).
N = numel(t);
a = find(t <= tc, 1, 'last');
if isempty(a), a = 1; end
a = min(max(a, 1), N - 1);
if ~isempty(J)
    ctr = (t(J) + t(J + 1)) / 2;
    [dmin, j] = min(abs(ctr - tc));
    if forceSnap || dmin <= tol
        a = J(j);
    end
end
end

