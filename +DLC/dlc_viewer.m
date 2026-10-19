function fig = dlc_viewer(default_path)
    data = shared.SessionData.instance();

    drawGUI(default_path);

    function drawGUI(default_path)
        % DLC viewer window with uigridlayout
        fig = uifigure('Name', 'DLC Viewer', 'Position', [100 100 1000 500], ...
            'CloseRequestFcn', @onClose);
        data.fig(1).dlc = fig;
        drawnow
        grid1 = uigridlayout(fig, [4 2]);
        grid1.Padding = [20,20,20,20];
        grid1.ColumnWidth = {'1x', 140};
        grid1.RowHeight = {30, 30, '1x', 30};
        
        hd = struct();
        %% Row 1: Folder and open button
        hd.path = uieditfield(grid1, 'text'); 
        if nargin>=1
            hd.path.Value = default_path;
        end
        uibutton(grid1, 'Text', 'Open DLC', 'ButtonPushedFcn', @openDLC);
    
        %% Row 2: DLC processing
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0], ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 2, 'Column', 1));
        subgrid1.ColumnWidth = {'1x', 30, 30, 30, 100, 80, 100};
            hd.info = uilabel(subgrid1,'Text',' Info:', 'BackgroundColor','w');
            hd.chk_x = uicheckbox(subgrid1,'Text','X','Value',1, ...
                'ValueChangedFcn', @checkXChanged);
            hd.chk_y = uicheckbox(subgrid1,'Text','Y','Value',1, ...
                'ValueChangedFcn', @checkYChanged);
            hd.chk_p = uicheckbox(subgrid1,'Text','P','Value',0, ...
                'ValueChangedFcn', @checkPChanged);
            uibutton(subgrid1,'Text','GetFrameRate', 'ButtonPushedFcn',@getFrameRate);
            hd.frameRate = uieditfield(subgrid1,'numeric','Value',1, ...
                'Limits', [0 Inf], 'LowerLimitInclusive', 'off', ...
                'ValueDisplayFormat','%.2f Hz','ValueChangedFcn', @frameRateChanged);
            hd.currentFrame = uieditfield(subgrid1,'numeric','Value',1, ...
                'ValueDisplayFormat','Frame: %d');
            
        % subgrid3 = uigridlayout(grid1, [1 2], 'Padding', [0 0 0 0]);
        % subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
        uibutton(grid1,'Text','DLC Fix', 'ButtonPushedFcn',@openFix);
            % hd.manualFix = uicheckbox(subgrid3,'Text','Man. Fix','Value', 0, ...
            %     'ValueChangedFcn',@manualFix);
        
    
        %% Row 3: DLC plot
        hd.ax = uiaxes(grid1); 
        hd.ax.Layout.Row = [3 4]; hd.ax.Layout.Column = 1;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        axis(hd.ax, 'ij'); 
        xlabel(hd.ax, 'Frame'); ylabel(hd.ax, 'Location (pixel)');
        disableDefaultInteractivity(hd.ax);

        hold(hd.ax, 'on');
        hd.ax.ButtonDownFcn = @axClicked;   % clicks on blank space

        hd.list_bodyparts = uilistbox(grid1, 'Multiselect', 'off', ...
            'Enable','off', 'ValueChangedFcn', @(src,evt)listChanged());
        hd.list_bodyparts.Layout.Row = 3; hd.list_bodyparts.Layout.Column = 2;
    
        %% Row 4:  zoom in, zoom out, update buttons        
        subgrid2 = uigridlayout(grid1, [1 4], 'Padding', [0 0 0 0]);
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
        hd.dataListener = addlistener(data, 'DataChanged', @(src, evt)showBodypart());
        hd.infoListener = addlistener(data, 'InfoChanged', @(src, evt)updateInfo());

        data.dlc(1).hd = hd;
    end

    function openDLC(~,~)
        hd = data.dlc.hd;
        filename = hd.path.Value;
        if isempty(filename)
            filename='*.csv';
        else
            [pathname, file, ext] = fileparts(filename);
            if isempty(ext)
                filename = fullfile(pathname, file, '*.csv');
            else
                filename = fullfile(pathname, ['*' ext]);
            end
        end
        [filename, pathname]=uigetfile(filename, 'Open DeepLabCut file');
        drawnow; figure(fig);
        if isequal(pathname,0), return; end
        filename=fullfile(pathname, filename);
        if ~exist(filename, "file"), return; end

        hd.path.Value = filename;
    
        % This reading function handles different kinds of data formats
        tabledlc = DLC.read_dlc(filename);
        data.dlc.table = tabledlc;
        data.dlc.seg = [];
        data.dlc.seg_bodypart = '';

        % update body part list
        hd.list_bodyparts.Enable = 'on';
        hd.list_bodyparts.Items = tabledlc.Properties.UserData;

        % axis(hd.ax,'tight');
        % ylim(hd.ax, [0 1200]);
        % xlim(hd.ax, [1 height(tabledlc)]);

        data.dlc.hd = hd;

        % update frame rate and total frames
        notify(data, 'InfoChanged')
        % draw trajectory plot
        notify(data, 'DataChanged');
        % draw time line
        updateDLCtime(data.currentTime);
    end

    function listChanged()
        notify(data,'DataChanged');
    end

    % main update function.=========================
    function showBodypart()
        if ~data.has('dlc'); return; end

        hd = data.dlc.hd;
        S = fixStyle();
        
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
    end

    % One legend entry per item. Fix layers exist twice (x and y copies with
    % the same DisplayName): use the x copy, or the y copy when x is hidden.
    % Hidden or empty layers are left out.
    function updateLegend(hd)
        S = fixStyle();
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
        attn = [{'Marker', 'o', 'MarkerSize', S.attnSize, 'LineWidth', S.attnWidth}, passThru];

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
        if data.has('gait')
            if isfield(data.gait.hd, 'stepXDLC') && ishghandle(data.gait.hd.stepXDLC)
                data.gait.hd.stepXDLC.Visible = src.Value && data.gait.hd.stepCheck.Value;
            end
        end
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
        if data.has('gait')
            if isfield(data.gait.hd, 'stepYDLC') && ishghandle(data.gait.hd.stepYDLC)
                data.gait.hd.stepYDLC.Visible = src.Value && data.gait.hd.stepCheck.Value;
            end
        end
    end

    function checkPChanged(src,~)
        hd = data.dlc.hd;
        if isfield(hd, 'pplot') && ishghandle(hd.pplot)
            hd.pplot.Visible = src.Value;
            hd.ax.YAxis(2).Visible = src.Value;
            updateLegend(hd);
        end
    end

    % button callback
    function getFrameRate(~,~)
        frameRate = data.getFrameRate();
        data.dlc.hd.frameRate.Value = frameRate;
        updateFrameRate(frameRate);
    end

    % manually change frame rate edit field.
    function frameRateChanged(src,~)
        data.setFrameRate(src.Value);
    end

    function updateFrameRate(frameRate)
        hd = data.dlc.hd;
        totalFrame = height(data.dlc.table);
        data.dlc.t = data.getFrameTimes(totalFrame);

        hd.frameRate.Value = frameRate;

        showBodypart();             % redraw trace and fix layers on new time base

        % update xlims if it's out of bound
        xlims = xlim(hd.ax);
        xlims = [max(xlims(1), data.dlc.t(1)) min(xlims(2), max(data.dlc.t, [], 'omitnan'))];
        if xlims(2) > xlims(1), xlim(hd.ax, xlims); end
        
        if hd.frameRate.Value == 1
            xlabel(hd.ax, 'Frame')
        else
            xlabel(hd.ax, 'Time (s)')
        end
    end

    % triggered by info event
    function updateInfo()
        if ~data.has('dlc'), return; end
        hd = data.dlc.hd;

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
        else
            % if window is already open, activate it.
            figure(hd.fixGUI)
        end
        data.dlc.hd = hd;
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
        [tempX, tempY, mask, seg] = DLC.dlc_fix_predict(xdata, ydata, [], [], seg);

        data.dlc.table.temp_x = tempX;
        data.dlc.table.temp_y = tempY;
        data.dlc.table.temp_likelihood = DLC.seg_likelihood(seg);
        data.dlc.seg = seg;
        notify(data, 'DataChanged');
    end

    % frame at such that the clicked jump lies between frames a and a+1
    function a = jumpAtClick(src, tc, t, seg, hd)
        S = fixStyle();
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


            % draw time line on the left side (see drawP)
            if numel(hd.ax.YAxis) > 1, yyaxis(hd.ax, 'left'); end
            hd = shared.myPlot(@xline, hd, 'timeline_dlc', hd.ax, ...
                data.currentTime,  'k', ...
                'HitTest', 'off', 'HandleVisibility', 'off');
            data.dlc.hd = hd;

            data.setTime(currentTime);
    
            % if time is out of current lims, move the zoom frame over.
            zoomlim = shared.zoom(get(hd.ax,'xLim'), currentTime, 'pan');
            data.setZoom(zoomlim);
        end
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
        hd=data.dlc.hd;
        % close fix GUI first.
        if isfield(hd, 'fixGUI') && isgraphics(hd.fixGUI)
            close(hd.fixGUI)
        end
        % Clear DLC markers on video
        if data.has('video')
            if isfield(data.video.hd, 'dlcMarker')
                delete(data.video.hd.dlcMarker)
                data.video.hd = rmfield(data.video.hd, 'dlcMarker');
            end
            if isfield(data.video.hd, 'dlcTempMarker')
                delete(data.video.hd.dlcTempMarker)
                data.video.hd = rmfield(data.video.hd, 'dlcTempMarker');
            end
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
        delete(src);  % finally close the GUI
    end
end

% ==========================================================================
% local helpers (no shared state)
% ==========================================================================
function S = fixStyle()
% All display choices and attention thresholds of the fix overlay.
% Magenta is reserved for gait markers; yellow is avoided (invisible on white).
C.blueDark  = [0.00 0.24 0.62];
C.blueLight = [0.35 0.66 1.00];
C.blueGrey  = [0.66 0.80 1.00];
C.green     = [0.10 0.62 0.15];
C.red       = [0.85 0.10 0.10];
C.orange    = [1.00 0.50 0.00];
C.grey      = [0.55 0.55 0.55];
C.yellow    = [0.90 0.80 0.00];

% traces
S.xColor = C.blueDark;          % x trace
S.yColor = C.blueLight;         % y trace
S.pColor = C.yellow;          % p trace
S.leftAxisColor = [0.15 0.15 0.15];   % MATLAB default; yyaxis would recolour it
S.trace  = 1;                   % trace line width

% interpolation (behind the trace)
S.interpColor = C.green;
S.interpStyle = ':';
S.interpWidth = 1;

% jumps (on top of the trace)
S.jumpColor = C.orange;
S.jumpStyle = '--';
S.jumpWidth = S.trace;

% frame markers; seeds made by the algorithm are not marked
S.good  = C.green;
S.bad   = C.red;
S.grey  = C.grey;
S.markSize  = 6;                % same for all frame markers
S.markWidth = 1;                % one step thicker than the default 0.5
S.goodMarker     = 'o';         % propagated good: open circle
S.userGoodMarker = 'o';         % user-made seed: filled circle
S.badMarker      = 'x';         % propagated bad
S.questMarker    = 'x';         % questionable (grey)
S.userBadMarker  = '*';         % user-made bad (user)
S.unflagMarker   = 'o';         % never reached (grey)

% needs attention: large circles at both ends
S.attnSize     = 14;
S.attnWidth    = 1.5;
S.attnConflict = C.orange;      % neighbouring good segments
S.attnLongBad  = C.red;         % bad segment of at least longBadFrac * win_width
S.attnInterp   = C.green;       % interpolation of at least longInterpFrac * win_width
S.longBadFrac    = 1/3;
S.longInterpFrac = 1;

% legend: order of the fix layers, and placement ('eastoutside' keeps it off the data)
S.legendOrder = {'interp', 'jump', 'good', 'bad', 'userGood', ...
                 'userBad', 'unflag', 'quest', 'attnConflict', 'attnLongBad', 'attnInterp'};
S.legendLocation = 'southeast';

% Displaynames for legends
S.legend.x = 'X';
S.legend.y = 'Y';
S.legend.p = 'P';
S.legend.interp = 'Interpolation';
S.legend.jump = 'Jump';
S.legend.good = 'Presumed good';
S.legend.bad = 'Presumed bad';
S.legend.quest = 'Questionable';
S.legend.unflag = 'Undetermined';
S.legend.userGood = 'User confirmed';
S.legend.userBad = 'User rejected';
S.legend.attnConflict = 'Attn: adjacent good';
S.legend.attnLongBad = 'Attn: long bad';
S.legend.attnInterp = 'Attn: long interp';

% clicks
S.snapPx = 6;                   % ctrl-click snaps to a jump within this many pixels
end

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

