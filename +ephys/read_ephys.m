function data = read_ephys(files)
% Read Open Ephys and convert it to Intan compatible format.
% go to https://github.com/open-ephys/open-ephys-matlab-tools
% for ephys reader installation and documentation.

if ~exist('Session', 'class')
    url = 'https://github.com/open-ephys/open-ephys-matlab-tools';
    fprintf(['Reading Open Ephys data needs open-ephys-matlab-tools (class Session).\n' ...
        'Install it from %s and add it to the MATLAB path.\n'], url);
    msgbox(sprintf(['Reading Open Ephys data needs open-ephys-matlab-tools.\n\n' ...
        'Install it from\n%s\nand add it to the MATLAB path.'], url), ...
        'Open Ephys reader missing', 'warn', 'modal');
    error('ephys:missingReader', 'open-ephys-matlab-tools is not on the MATLAB path.');
end

session = Session(files);
data = struct();
if isempty(session.recordNodes); return; end

nodeIndex = choose(arrayfun(@(k)sprintf('Record node %d',k), 1:numel(session.recordNodes), ...
    'UniformOutput',false), 'Select record node:');
node = session.recordNodes{nodeIndex};
recordingIndex = choose(arrayfun(@(k)sprintf('Recording %d',k), 1:numel(node.recordings), ...
    'UniformOutput',false), 'Select recording:');
rec = node.recordings{recordingIndex};
keys = rec.continuous.keys();
streamIndex = choose(keys, 'Select continuous stream:');
keyName = keys{streamIndex};
recording = rec.continuous(keyName);

channelNames = recording.metadata.names;
data.sampleRate = recording.metadata.sampleRate;

% get data from analog channels
analogChans = startsWith(channelNames, 'CH');
if any(analogChans)
    data.analogData = double(recording.samples(analogChans,:)');
    data.analogUnits = 'counts';
    data.analogChannels = channelNames(analogChans);
end

% get data from ADC channels
adcChans = startsWith(channelNames, 'ADC');
if any(adcChans)
    data.adcData = double(recording.samples(adcChans,:)');
end

% BinaryRecording exposes raw counts. Match the selected stream's metadata.
if strcmpi(rec.format, 'Binary')
    streams = rec.info.continuous;
    folders = cellfun(@(v)regexprep(char(v),'[/\\]+$',''), {streams.folder_name}, 'UniformOutput',false);
    idx = find(strcmp(folders, char(recording.metadata.streamName)),1);
    if isempty(idx), error('ephys:units:stream','Cannot locate scaling metadata for the selected stream.'); end
    channels = streams(idx).channels;
    if any(analogChans)
        data.analogData = ephys.scale_binary_channels(data.analogData, channels(analogChans), 'uV');
        data.analogUnits = 'uV';
    end
    if any(adcChans)
        data.adcData = ephys.scale_binary_channels(data.adcData, channels(adcChans), 'V');
        data.adcUnits = 'V';
    end
else
    warning('ephys:units:unscaled','This Open Ephys format has not been calibrated here; displaying raw counts.');
end

% TTL lines as digital channels (see ephys.ttl_channels); the camera trigger
% is chosen in the Ephys viewer
events = rec.ttlEvents;
if isKey(events, keyName)
    ttl = events(keyName);
    lines = unique(ttl.line);
    start = recording.metadata.startTimestamp;
    data.digital = struct('name', {}, 'rise', {}, 'fall', {});
    for k = 1:numel(lines)
        onLine = ttl.line == lines(k);
        data.digital(k).name = sprintf('TTL-%02d', lines(k));
        data.digital(k).rise = sort(ttl.timestamp(onLine & ttl.state == 1) - start);
        data.digital(k).fall = sort(ttl.timestamp(onLine & ttl.state == 0) - start);
    end
end

% get time sample
data.t = recording.timestamps(:) - recording.metadata.startTimestamp;

% save files
data.files = files;
end



function idx = choose(labels,prompt)
if isempty(labels), error('ephys:emptyRecording','No recording sources found.'); end
idx = 1;
if numel(labels)>1
    [idx,ok] = listdlg('PromptString',prompt,'ListString',labels, ...
        'SelectionMode','single','ListSize',[380 200]);
    if ~ok, error('ephys:cancelled','Recording selection cancelled.'); end
end
end
