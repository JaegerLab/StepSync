function g = read_gait(filename)
% g = gait.read_gait(filename)
% Read and check a gait .mat file written by gait.save_gait. Errors:
%   gait:file:format  not a StepSync gait file, or incomplete
%   gait:file:older   saved before format 2 (snake_case fields)
%   gait:file:newer   saved by a newer StepSync

    VERSION = 2;
    [~, name, ext] = fileparts(filename);
    name = [name ext];
    vars = who('-file', filename);
    if ~all(ismember({'fileFormat', 'formatVersion', 'gait'}, vars))
        error('gait:file:format', '%s is not a StepSync gait file.', name);
    end
    f = load(filename, 'fileFormat', 'formatVersion', 'gait');
    if ~isequal(f.fileFormat, 'StepSync gait')
        error('gait:file:format', '%s is not a StepSync gait file.', name);
    end
    if f.formatVersion > VERSION
        error('gait:file:newer', '%s was saved by a newer StepSync (format %g; this version reads format %d).', ...
            name, f.formatVersion, VERSION);
    elseif f.formatVersion < VERSION
        error('gait:file:older', '%s has an older gait format (%g); this version reads format %d.', ...
            name, f.formatVersion, VERSION);
    end
    g = f.gait;

    required = {'paw', 'selection', 'mask', 'source', 'resolution', 'minInterval', 'frameRate'};
    missing = required(~isfield(g, required));
    if ~isempty(missing)
        error('gait:file:format', '%s is incomplete: %s missing.', name, strjoin(missing, ', '));
    end
    if isempty(g.paw) || ~all(isfield(g.paw, {'name', 'rawX', 'rawY', 'thresh'}))
        error('gait:file:format', '%s has no paws.', name);
    end
    n = numel(g.paw(1).rawX);
    if any(arrayfun(@(p)numel(p.rawX) ~= n || numel(p.rawY) ~= n, g.paw)) || numel(g.mask) ~= n
        error('gait:file:format', '%s: paws and mask differ in length.', name);
    end
    defaults = struct('filename', '', 'maskParam', [], 'sta', struct([]), 'timeRange', []);
    for f = fieldnames(defaults)'
        if ~isfield(g, f{1}), g.(f{1}) = defaults.(f{1}); end
    end
    if isempty(g.filename), g.filename = ''; end   % [] after a round trip
    for k = 1:numel(g.paw)   % files before the near-zero field: automatic
        if ~isfield(g.paw(k).thresh, 'nearZero'), g.paw(k).thresh.nearZero = NaN; end
    end
    if ~isscalar(g.selection.paw) || g.selection.paw < 1 || g.selection.paw > numel(g.paw)
        g.selection.paw = 1;
    end
end
