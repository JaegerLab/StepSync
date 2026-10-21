function tabledlc = crop_table(tabledlc, t, range)
% tabledlc = DLC.crop_table(tabledlc, t, range)
% Keep the rows (frames) whose time t lies in range = [t1 t2]. Their frame
% numbers are kept in Properties.CustomProperties.FrameIndex, so
% DLC.save_csv writes them to the index column and reopening the file
% puts the rows back on the same frames.

    frames = (1:height(tabledlc))';
    if isprop(tabledlc.Properties.CustomProperties, 'FrameIndex') && ...
            numel(tabledlc.Properties.CustomProperties.FrameIndex) == height(tabledlc)
        frames = tabledlc.Properties.CustomProperties.FrameIndex(:);
    else
        tabledlc = addprop(tabledlc, 'FrameIndex', 'table');
    end
    keep = t(:) >= range(1) & t(:) <= range(2);
    tabledlc = tabledlc(keep, :);
    tabledlc.Properties.CustomProperties.FrameIndex = frames(keep);
end
