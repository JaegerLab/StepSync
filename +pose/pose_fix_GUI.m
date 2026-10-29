function fig = pose_fix_GUI(mousePos)
% GUI for auto fix pose errors

    data = shared.SessionData.instance();
    
    %% draw GUI
    % grid 4x3
    mousePos(2)=mousePos(2)-120;
    fig = uifigure('Name', 'Pose auto fix', 'Position', shared.place_window([mousePos 300 250]), ...
        'CloseRequestFcn', @onClose);
    grid1 = uigridlayout(fig, [4 2], "RowHeight",{30,30,30,'1x'});

    % line 1 - high pass filter
    jumpthresh = uieditfield(grid1,'numeric','Value',20, ...
                'ValueDisplayFormat','Jump thresh: %.1f px');
    winwidth = uieditfield(grid1, 'numeric','Value', 60, ...
                'ValueDisplayFormat','Win width: %d frame');

    % line 2 - auto parameter
    uibutton(grid1, 'Text', 'Auto jump thresh', 'ButtonPushedFcn', @autoThresh);
    uibutton(grid1, 'Text', 'Auto seg width', 'ButtonPushedFcn', @autoWidth);

    % line 3 - buttons: preview, save as
    uibutton(grid1, 'Text','Preview', 'ButtonPushedFcn', @(~,~)preview);
    uibutton(grid1, 'Text','Save As', 'ButtonPushedFcn', @(~,~)saveAs);

    % line 4 - user instruction
    txt = sprintf(['After Preview\n' ...
        'Pose :\t Ctrl-click: add/remove jump between 2 frames.\n' ...
        '\t\t Shift-click: toggle segment good/bad.\n' ...
        '\t\t Orange: neighbouring good segments, check.\n' ...
        'Video:\t Click and drag: Refine label position.']);
    uilabel(grid1, 'Text', txt , ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 4, 'Column', [1 2]));

    autoThresh()
    autoWidth()
    drawnow

    function preview()
        if ~data.has('pose'), return; end

        if ismember('temp_x', data.pose.table.Properties.VariableNames)
            if isfield(data.pose, 'segBodypart')
                msg = sprintf(' for %s', data.pose.segBodypart);
            else 
                msg = '';
            end
            msg = sprintf('Discard the previous preview%s?', msg);
            selection = uiconfirm(fig, msg, 'Confirm Discard');
            if strcmp(selection, 'Cancel'), return; end
        end

        field = data.pose.hd.bodypart.Value;
        xdata = data.pose.table.([field '_x']);
        ydata = data.pose.table.([field '_y']);
        
        [tempX, tempY, mask, seg] = pose.pose_fix(xdata,ydata, ...
            jumpthresh.Value, winwidth.Value);

        data.pose.table.temp_x = tempX;
        data.pose.table.temp_y = tempY;

        data.pose.table.temp_likelihood = pose.seg_likelihood(seg);

        % segments, for display and click editing in pose_viewer
        data.pose.seg = seg;
        data.pose.segBodypart = field;
        data.pose.previewParameters = [jumpthresh.Value winwidth.Value]; % for the Save As name
        
        % plot comparison
        data.notifyPose('preview');
    end

    function saveAs()
        if ~data.has('pose'), return; end

        if ~ismember('temp_x', data.pose.table.Properties.VariableNames) || ...
                ~isfield(data.pose, 'segBodypart') || ...
                ~strcmp(data.pose.segBodypart, data.pose.hd.bodypart.Value) 
            uialert(fig, 'Preview first.');
            return;
        end

        % get new body part name to save
        opt.WindowStyle = 'modal';
        opt.Interpreter = 'none';
        % name after the previewed parameters; the fields may have changed since
        params = [jumpthresh.Value winwidth.Value];
        if isfield(data.pose, 'previewParameters') && numel(data.pose.previewParameters) == 2
            params = data.pose.previewParameters;
        end
        newName = sprintf('%s_FixJ%gW%d', data.pose.hd.bodypart.Value, params(1), params(2));
        newName = inputdlg('Enter new name:', 'Save As', [1 30], {newName}, opt);
        if isempty(newName), return; end
        newName = newName{1};

        % overwrite?
        overwrite = false;
        if ismember([newName '_x'], data.pose.table.Properties.VariableNames)
            selection = questdlg('Variable exists. Overwrite?','Warning', 'Yes','No','No');
            if ~strcmp(selection,'Yes'), return; end % if no, abort
            data.pose.table = removevars(data.pose.table, ...
                {[newName '_x'],[newName '_y'],[newName '_likelihood']});
            % flag overwritten so the name won't be added repeatedly
            overwrite = true;
        end

        % rename temp to new name
        data.pose.table = renamevars(data.pose.table, ...
            {'temp_x', 'temp_y', 'temp_likelihood'}, ...
            {[newName '_x'],[newName '_y'],[newName '_likelihood']});

        removeTempPlots()

        % update list and plot
        if ~overwrite
            data.pose.hd.bodypart.Items{end+1} = newName;
            data.pose.table.Properties.UserData{end+1} = newName;
        end
        data.pose.hd.bodypart.Value = newName;
        data.notifyPose('commit', {newName});
    end

    function removeTempPlots()
        % remove fix layers (fix_*) in the Pose viewer and forget the segments
        f = fieldnames(data.pose.hd);
        f = f(strncmp(f, 'fix_', 4));
        for i = 1:numel(f)
            if ishghandle(data.pose.hd.(f{i})), delete(data.pose.hd.(f{i})); end
        end
        data.pose.hd = rmfield(data.pose.hd, f);
        data.pose.seg = [];
        data.pose.segBodypart = '';
        % the video viewer hides its preview marker on the next PoseChanged
    end

    function autoThresh(~,~)
        if ~data.has('pose'), return; end
        field = data.pose.hd.bodypart.Value;
        xdata = data.pose.table.([field '_x']);
        ydata = data.pose.table.([field '_y']);
        [thr, ~] = pose.auto_jump_threshold(xdata, ydata);
        jumpthresh.Value = round(thr,1);
    end

    function autoWidth(~,~)
        if ~data.has('pose'), return; end
        field = data.pose.hd.bodypart.Value;
        xdata = data.pose.table.([field '_x']);
        ydata = data.pose.table.([field '_y']);
        thr = jumpthresh.Value;
        [w, ~] = pose.auto_window_width(xdata, ydata, thr);
        winwidth.Value = round(w);
    end

    function onClose(src, ~)
        if data.has('pose')
            if ismember('temp_x', data.pose.table.Properties.VariableNames)
                data.pose.table = removevars(data.pose.table, {'temp_x', 'temp_y', 'temp_likelihood'});
            end
            removeTempPlots();
            data.notifyPose('preview');
        end
        
        data.pose.hd = rmfield(data.pose.hd, 'fixGUI');
        delete(src)
        notify(data, 'WindowsChanged');
    end

end
