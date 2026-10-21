function [tabledlc, how] = align_frames(tabledlc, nVideoFrames)
% [tabledlc, how] = DLC.align_frames(tabledlc, nVideoFrames)
% Put a pose table on the frame grid of the video, using the frame numbers
% read from the file (Properties.CustomProperties.FrameIndex, 1-based).
%   nVideoFrames  frames in the open video, [] without video
%   how           'as is'    rows are frames 1..n already
%                 'shifted'  the video has as many frames as the table (a
%                            video cropped the same way): rows become 1..n
%                 'padded'   NaN rows fill the frames missing from the file,
%                            up to the video length (or the last frame
%                            number without a long enough video)
% Afterwards FrameIndex is 1..height.

    frames = (1:height(tabledlc))';
    hasIndex = isprop(tabledlc.Properties.CustomProperties, 'FrameIndex') && ...
        ~isempty(tabledlc.Properties.CustomProperties.FrameIndex);
    if hasIndex
        frames = tabledlc.Properties.CustomProperties.FrameIndex(:);
    else
        tabledlc = addprop(tabledlc, 'FrameIndex', 'table');
    end
    validateattributes(frames, {'numeric'}, {'vector', 'integer', 'positive', 'numel', height(tabledlc)});
    if numel(unique(frames)) ~= numel(frames)
        error('DLC:frames:duplicates', 'The pose file has duplicate frame indices.');
    end

    n = height(tabledlc);
    if isequal(frames, (1:n)')
        how = 'as is';
    elseif ~isempty(nVideoFrames) && nVideoFrames == n
        how = 'shifted';
    else
        how = 'padded';
        total = max(frames);
        if ~isempty(nVideoFrames), total = max(total, nVideoFrames); end
        if ~all(varfun(@isnumeric, tabledlc, 'OutputFormat', 'uniform'))
            error('DLC:frames:type', 'Only numeric pose tables can be padded.');
        end
        values = nan(total, width(tabledlc));
        values(frames, :) = tabledlc{:, :};
        padded = array2table(values, 'VariableNames', tabledlc.Properties.VariableNames);
        % body parts, source, scorer
        padded.Properties.UserData = tabledlc.Properties.UserData;
        padded.Properties.Description = tabledlc.Properties.Description;
        custom = properties(tabledlc.Properties.CustomProperties);
        padded = addprop(padded, custom, repmat({'table'}, size(custom)));
        for k = 1:numel(custom)
            padded.Properties.CustomProperties.(custom{k}) = tabledlc.Properties.CustomProperties.(custom{k});
        end
        tabledlc = padded;
    end
    tabledlc.Properties.CustomProperties.FrameIndex = (1:height(tabledlc))';
end
