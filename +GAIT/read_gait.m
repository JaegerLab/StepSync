function g = read_gait(filename)
% g = GAIT.read_gait(filename)
% Read and check a gait .mat file written by GAIT.save_gait. Errors:
%   GAIT:file:format  not a StepSync gait file, or incomplete
%   GAIT:file:newer   saved by a newer StepSync

    VERSION = 1;
    [~, name, ext] = fileparts(filename);
    name = [name ext];
    vars = who('-file', filename);
    if ~all(ismember({'fileFormat', 'formatVersion', 'gait'}, vars))
        error('GAIT:file:format', '%s is not a StepSync gait file.', name);
    end
    f = load(filename, 'fileFormat', 'formatVersion', 'gait');
    if ~isequal(f.fileFormat, 'StepSync gait')
        error('GAIT:file:format', '%s is not a StepSync gait file.', name);
    end
    if f.formatVersion > VERSION
        error('GAIT:file:newer', '%s was saved by a newer StepSync (format %g; this version reads format %d).', ...
            name, f.formatVersion, VERSION);
    end
    g = f.gait;

    required = {'paw', 'selection', 'mask', 'source', 'resolution', 'minInterval', 'frameRate'};
    missing = required(~isfield(g, required));
    if ~isempty(missing)
        error('GAIT:file:format', '%s is incomplete: %s missing.', name, strjoin(missing, ', '));
    end
    if isempty(g.paw) || ~all(isfield(g.paw, {'name', 'raw_x', 'raw_y', 'thresh'}))
        error('GAIT:file:format', '%s has no paws.', name);
    end
    n = numel(g.paw(1).raw_x);
    if any(arrayfun(@(p)numel(p.raw_x) ~= n || numel(p.raw_y) ~= n, g.paw)) || numel(g.mask) ~= n
        error('GAIT:file:format', '%s: paws and mask differ in length.', name);
    end
    defaults = struct('filename', '', 'maskParam', [], 'sta', struct([]), 'time_range', []);
    for f = fieldnames(defaults)'
        if ~isfield(g, f{1}), g.(f{1}) = defaults.(f{1}); end
    end
    if isempty(g.filename), g.filename = ''; end   % [] after a round trip
    if ~isscalar(g.selection.paw) || g.selection.paw < 1 || g.selection.paw > numel(g.paw)
        g.selection.paw = 1;
    end
end
