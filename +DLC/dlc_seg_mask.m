function mask = dlc_seg_mask(seg)
%DLC_SEG_MASK  Frame-level good mask from a segment structure (flag > 0).
%
%   mask = DLC.dlc_seg_mask(seg)   returns an n_frames x 1 logical vector.

mask = repelem(seg.flag(:) > 0, seg.len(:));
end
