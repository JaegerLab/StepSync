function tabledlc = read_slp(filename)
% Reconstruct one track on the original zero-based SLEAP frame grid.
raw = readtable(filename);
if ~ismember('frame_idx', raw.Properties.VariableNames)
    error('DLC:SLEAP:frames', 'SLEAP CSV must contain frame_idx.');
end
if ismember('track', raw.Properties.VariableNames)
    tracks = unique(string(raw.track), 'stable');
    if numel(tracks) > 1
        [idx, ok] = listdlg('PromptString', 'Select one SLEAP track:', ...
            'ListString', cellstr(tracks), 'SelectionMode', 'single');
        if ~ok, error('DLC:SLEAP:cancelled', 'Track selection cancelled.'); end
        raw = raw(string(raw.track)==tracks(idx),:);
    end
end
frames = raw.frame_idx;
validateattributes(frames, {'numeric'}, {'vector','finite','integer','nonnegative','nonempty'});
if numel(unique(frames)) ~= numel(frames)
    error('DLC:SLEAP:duplicates', 'Selected track has duplicate frame indices.');
end
metadata = intersect({'track','frame_idx','instance_score'}, raw.Properties.VariableNames);
raw = removevars(raw, metadata);
vars = replace(raw.Properties.VariableNames, '_score', '_likelihood');
raw.Properties.VariableNames = vars;
values = nan(max(frames)+1, width(raw));
values(frames+1,:) = raw{:,:};
tabledlc = array2table(values, 'VariableNames', vars);
xvars = vars(endsWith(vars, '_x'));
tabledlc.Properties.UserData = cellfun(@(v)v(1:end-2), xvars, 'UniformOutput', false);
tabledlc.Properties.Description = filename;
end
