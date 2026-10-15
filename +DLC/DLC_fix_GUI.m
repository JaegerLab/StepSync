function fig = DLC_fix_GUI(mousePos)
% GUI for auto fix DLC errors

    data = shared.SessionData.instance();
    
    %% draw GUI
    % grid 4x3
    mousePos(2)=mousePos(2)-120;
    fig = uifigure('Name', 'DLC auto fix', 'Position', [mousePos 300 250], ...
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
        'DLC  :\t Ctrl-click: add/remove jump between 2 frames.\n' ...
        '\t\t Shift-click: toggle segment good/bad.\n' ...
        '\t\t Orange: neighbouring good segments, check.\n' ...
        'Video:\t Click and drag: Refine label position.']);
    uilabel(grid1, 'Text', txt , ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 4, 'Column', [1 2]));

    autoThresh()
    autoWidth()
    drawnow

    function preview()
        if ~data.has('dlc'), return; end
        field = data.dlc.hd.list_bodyparts.Value;
        xdata = data.dlc.table.([field '_x']);
        ydata = data.dlc.table.([field '_y']);
        
        [tempX, tempY, mask, seg] = DLC.dlc_fix_predict(xdata,ydata, ...
            jumpthresh.Value, winwidth.Value);

        data.dlc.table.temp_x = tempX;
        data.dlc.table.temp_y = tempY;

        % rebuild likelihood
        if isfield(data.dlc, 'seg') && ~isempty(data.dlc.seg) && ...
                data.dlc.seg.n_frames == height(data.dlc.table)
            data.dlc.table.temp_likelihood = seg_likelihood(seg);
        else
            % use mask as likelihood. good=1, bad=0;
            data.dlc.table.temp_likelihood = double(mask);
        end

        % segments, for display and click editing in dlc_viewer
        data.dlc.seg = seg;
        data.dlc.seg_bodypart = field;
        data.dlc.previewParameters = [jumpthresh.Value winwidth.Value];
        
        % plot comparison
        notify(data, 'DataChanged');
    end

    function saveAs()
        if ~data.has('dlc'), return; end

        if ~ismember('temp_x', data.dlc.table.Properties.VariableNames) || ...
                ~isfield(data.dlc, 'seg_bodypart') || ...
                ~strcmp(data.dlc.seg_bodypart, data.dlc.hd.list_bodyparts.Value) || ...
                ~isfield(data.dlc, 'previewParameters') || ...
                ~isequal(data.dlc.previewParameters, [jumpthresh.Value winwidth.Value])
            preview;
        end

        % get new body part name to save
        opt.WindowStyle = 'modal';
        opt.Interpreter = 'none';
        newName = sprintf('%s_FixJ%gW%d', ...
                data.dlc.hd.list_bodyparts.Value, jumpthresh.Value, winwidth.Value);
        newName = inputdlg('Enter new name:', 'Save As', [1 30], {newName}, opt);
        if isempty(newName), return; end
        newName = newName{1};

        % overwrite?
        overwrite = false;
        if ismember([newName '_x'], data.dlc.table.Properties.VariableNames)
            selection = questdlg('Variable exists. Overwrite?','Warning', 'Yes','No','No');
            if ~strcmp(selection,'Yes'), return; end % if no, abort
            data.dlc.table = removevars(data.dlc.table, ...
                {[newName '_x'],[newName '_y'],[newName '_likelihood']});
            % flag overwritten so the name won't be added repeatedly
            overwrite = true;
        end

        % rename temp to new name
        data.dlc.table = renamevars(data.dlc.table, ...
            {'temp_x', 'temp_y', 'temp_likelihood'}, ...
            {[newName '_x'],[newName '_y'],[newName '_likelihood']});

        removeTempPlots()

        % update list and plot
        if ~overwrite
            data.dlc.hd.list_bodyparts.Items{end+1} = newName;
            data.dlc.table.Properties.UserData{end+1} = newName;
        end
        data.dlc.hd.list_bodyparts.Value = newName;
        notify(data, 'DataChanged');
    end

    function removeTempPlots()
        % remove fix layers (fix_*) in dlc viewer and forget the segments
        f = fieldnames(data.dlc.hd);
        f = f(strncmp(f, 'fix_', 4));
        for i = 1:numel(f)
            if ishghandle(data.dlc.hd.(f{i})), delete(data.dlc.hd.(f{i})); end
        end
        data.dlc.hd = rmfield(data.dlc.hd, f);
        data.dlc.seg = [];
        data.dlc.seg_bodypart = '';

        % remove temp marker drawn in video viewer
        if data.has('video') && isfield(data.video.hd, 'dlcTempMarker')
            delete(data.video.hd.dlcTempMarker)
            data.video.hd = rmfield(data.video.hd, 'dlcTempMarker');
        end
    end

    function autoThresh(~,~)
        if ~data.has('dlc'), return; end
        field = data.dlc.hd.list_bodyparts.Value;
        xdata = data.dlc.table.([field '_x']);
        ydata = data.dlc.table.([field '_y']);
        [thr, ~] = DLC.auto_jump_threshold(xdata, ydata);
        jumpthresh.Value = round(thr,1);
    end

    function autoWidth(~,~)
        if ~data.has('dlc'), return; end
        field = data.dlc.hd.list_bodyparts.Value;
        xdata = data.dlc.table.([field '_x']);
        ydata = data.dlc.table.([field '_y']);
        thr = jumpthresh.Value;
        [w, ~] = DLC.auto_window_width(xdata, ydata, thr);
        winwidth.Value = round(w);
    end

    function onClose(src, ~)
        if data.has('dlc')
            if ismember('temp_x', data.dlc.table.Properties.VariableNames)
                data.dlc.table = removevars(data.dlc.table, {'temp_x', 'temp_y', 'temp_likelihood'});
            end
            removeTempPlots();
            notify(data, 'DataChanged');
        end
        
        data.dlc.hd = rmfield(data.dlc.hd, 'fixGUI');
        delete(src)
    end

    function p = seg_likelihood(seg)
        %DLC_SEG_LIKELIHOOD  Per-frame likelihood rebuilt from segment flags.
        %
        %   p = DLC.dlc_seg_likelihood(seg)   returns an n_frames x 1 vector.
        %
        %   Used when a fixed trace is saved as a new body part, so that its
        %   _likelihood column says how much each frame can be trusted.
        
        % ---- values per flag (tune here) -----------------------------------------
        P_USER_GOOD = 1;      % flag  2, shorter than win_width (confirmed by the user)
        P_SEED      = 0.95;   % flag  2, seed made by the algorithm
        P_GOOD      = 0.9;    % flag  1, presumed good (propagation)
        P_UNSURE    = 0.5;    % flag -2 questionable, flag 0 unflagged
        P_BAD       = 0.1;    % flag -1, presumed bad (propagation)
        P_USER_BAD  = 0;      % flag -3, rejected by the user
        
        f = seg.flag(:);
        isSeed   = f == 2;
        userGood = isSeed & ~(seg.len(:) >= seg.win_width);   % NaN win_width: all user
        
        pk = P_UNSURE * ones(size(f));
        pk(isSeed)   = P_SEED;
        pk(userGood) = P_USER_GOOD;
        pk(f == 1)   = P_GOOD;
        pk(f == -1)  = P_BAD;
        pk(f == -3)  = P_USER_BAD;
        
        p = repelem(pk, seg.len(:));
    end
end