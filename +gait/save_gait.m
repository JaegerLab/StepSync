function save_gait(filename, gaitData, settings, frameRate, range)
% gaitData.save_gait(filename, gaitData, settings, frameRate, range)
% Write the gaitData data to a .mat file (-v7.3):
%   fileFormat = 'StepSync gait', formatVersion = 2
%   gaitData  paw (name, rawX, rawY in pixels, thresh per trace), selection,
%         mask, maskParam, sta, source, filename (the pose file),
%         resolution, minInterval, frameRate, timeRange
% settings: struct with resolution (px/cm) and minInterval (s), from the viewer.
% Steps, speeds and cm traces are not saved: Open recalculates them.
% range: [] (default) for the full length, or [t1 t2]: frames outside the
%        window become NaN and are masked out; the length stays the same,
%        so frames keep their numbers.

    if nargin < 5, range = []; end
    nFrames = numel(gaitData.paw(1).rawX);
    out = struct();
    out.fileFormat = 'StepSync gait';
    out.formatVersion = 2;

    g = struct();
    g.paw = struct('name', {gaitData.paw.name}, 'rawX', {gaitData.paw.rawX}, ...
        'rawY', {gaitData.paw.rawY}, 'thresh', {gaitData.paw.thresh});
    g.selection = gaitData.selection;
    g.mask = true(nFrames, 1);
    if isfield(gaitData, 'mask'), g.mask = logical(gaitData.mask(:)); end
    g.maskParam = [];
    if isfield(gaitData, 'maskParam'), g.maskParam = gaitData.maskParam; end
    g.sta = struct([]);
    if isfield(gaitData, 'sta'), g.sta = gaitData.sta; end
    g.source = gaitData.source;
    g.filename = '';
    if isfield(gaitData, 'filename'), g.filename = gaitData.filename; end
    g.resolution = settings.resolution;
    g.minInterval = settings.minInterval;
    g.frameRate = frameRate;
    g.timeRange = range;

    if ~isempty(range)
        outside = ~(gaitData.t(:) >= range(1) & gaitData.t(:) <= range(2));
        for k = 1:numel(g.paw)
            g.paw(k).rawX(outside) = NaN;
            g.paw(k).rawY(outside) = NaN;
        end
        g.mask(outside) = false;
    end
    out.gait = g;
    save(filename, '-struct', 'out', '-v7.3');
end
