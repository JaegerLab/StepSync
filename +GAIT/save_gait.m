function save_gait(filename, gait, settings, frameRate, range)
% GAIT.save_gait(filename, gait, settings, frameRate, range)
% Write the gait data to a .mat file (-v7.3):
%   fileFormat = 'StepSync gait', formatVersion = 1
%   gait  paw (name, raw_x, raw_y in pixels, thresh per trace), selection,
%         mask, maskParam, sta, source, filename (the DLC file),
%         resolution, minInterval, frameRate, time_range
% settings: struct with resolution (px/cm) and minInterval (s), from the viewer.
% Steps, speeds and cm traces are not saved: Open recalculates them.
% range: [] (default) for the full length, or [t1 t2]: frames outside the
%        window become NaN and are masked out; the length stays the same,
%        so frames keep their numbers.

    if nargin < 5, range = []; end
    nFrames = numel(gait.paw(1).raw_x);
    out = struct();
    out.fileFormat = 'StepSync gait';
    out.formatVersion = 1;

    g = struct();
    g.paw = struct('name', {gait.paw.name}, 'raw_x', {gait.paw.raw_x}, ...
        'raw_y', {gait.paw.raw_y}, 'thresh', {gait.paw.thresh});
    g.selection = gait.selection;
    g.mask = true(nFrames, 1);
    if isfield(gait, 'mask'), g.mask = logical(gait.mask(:)); end
    g.maskParam = [];
    if isfield(gait, 'maskParam'), g.maskParam = gait.maskParam; end
    g.sta = struct([]);
    if isfield(gait, 'sta'), g.sta = gait.sta; end
    g.source = gait.source;
    g.filename = '';
    if isfield(gait, 'filename'), g.filename = gait.filename; end
    g.resolution = settings.resolution;
    g.minInterval = settings.minInterval;
    g.frameRate = frameRate;
    g.time_range = range;

    if ~isempty(range)
        outside = ~(gait.t(:) >= range(1) & gait.t(:) <= range(2));
        for k = 1:numel(g.paw)
            g.paw(k).raw_x(outside) = NaN;
            g.paw(k).raw_y(outside) = NaN;
        end
        g.mask(outside) = false;
    end
    out.gait = g;
    save(filename, '-struct', 'out', '-v7.3');
end
