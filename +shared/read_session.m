function saved = read_session(filename)
% saved = shared.read_session(filename)
% Load a session .mat file and check its format. Errors:
%   StepSync:session:format  not a session file (also sessions saved before
%                            format version 3, which carry no format marker)
%   StepSync:session:newer   saved by a newer StepSync
%   StepSync:session:older   an older format version
%   StepSync:zoom            zoom limits not increasing

    VERSION = 4;
    saved = load(filename);
    [~, name, ext] = fileparts(filename);
    name = [name ext];

    if ~isfield(saved, 'fileFormat') || ~isequal(saved.fileFormat, 'StepSync session') || ...
            ~isfield(saved, 'formatVersion')
        error('StepSync:session:format', ...
            '%s is not a StepSync session file, or was saved by an older StepSync.', name);
    end
    if saved.formatVersion > VERSION
        error('StepSync:session:newer', ...
            '%s was saved by a newer StepSync (format %g; this version reads format %d).', ...
            name, saved.formatVersion, VERSION);
    elseif saved.formatVersion < VERSION
        error('StepSync:session:older', ...
            '%s has an older session format (%g); this version reads format %d.', ...
            name, saved.formatVersion, VERSION);
    end

    required = {'frameRate', 'currentTime', 'currentZoom', 'figures'};
    if ~all(isfield(saved, required))
        error('StepSync:session:format', '%s is incomplete: %s missing.', name, ...
            strjoin(required(~isfield(saved, required)), ', '));
    end
    unknown = setdiff(fieldnames(saved.figures), {'video', 'ephys', 'pose', 'gait'});
    if ~isempty(unknown)
        error('StepSync:session:format', '%s has unknown modules: %s.', name, strjoin(unknown, ', '));
    end
    validateattributes(saved.frameRate, {'numeric'}, {'scalar','finite','nonnegative'});
    validateattributes(saved.currentTime, {'numeric'}, {'scalar','finite','nonnegative'});
    validateattributes(saved.currentZoom, {'numeric'}, {'vector','numel',2,'finite'});
    if saved.currentZoom(2) <= saved.currentZoom(1)
        error('StepSync:zoom', 'Saved zoom limits must be increasing.');
    end
end
