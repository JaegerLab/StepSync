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
    error('EMG:missingReader', 'open-ephys-matlab-tools is not on the MATLAB path.');
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
key_name = keys{streamIndex};
recording = rec.continuous(key_name);

channel_names = recording.metadata.names;
data.sample_rate = recording.metadata.sampleRate;

% get data from analog channels
analog_chans = startsWith(channel_names, 'CH');
if any(analog_chans)
    data.analog_data = double(recording.samples(analog_chans,:)');
    data.analog_units = 'counts';
    data.analog_channels = channel_names(analog_chans);
end

% get data from ADC channels
adc_chans = startsWith(channel_names, 'ADC');
if any(adc_chans)
    data.adc_data = double(recording.samples(adc_chans,:)');
end

% BinaryRecording exposes raw counts. Match the selected stream's metadata.
if strcmpi(rec.format, 'Binary')
    streams = rec.info.continuous;
    folders = cellfun(@(v)regexprep(char(v),'[/\\]+$',''), {streams.folder_name}, 'UniformOutput',false);
    idx = find(strcmp(folders, char(recording.metadata.streamName)),1);
    if isempty(idx), error('EMG:units:stream','Cannot locate scaling metadata for the selected stream.'); end
    channels = streams(idx).channels;
    if any(analog_chans)
        data.analog_data = EMG.scale_binary_channels(data.analog_data, channels(analog_chans), 'uV');
        data.analog_units = 'uV';
    end
    if any(adc_chans)
        data.adc_data = EMG.scale_binary_channels(data.adc_data, channels(adc_chans), 'V');
        data.adc_units = 'V';
    end
else
    warning('EMG:units:unscaled','This Open Ephys format has not been calibrated here; displaying raw counts.');
end

% get trigger event time
events = rec.ttlEvents;
if isKey(events, key_name)
    triggers = events(key_name);
    rising = triggers.state == 1;
    lines = unique(triggers.line(rising));
    if numel(lines) > 1
        labels = cell(numel(lines),1);
        for k = 1:numel(lines)
            times = triggers.timestamp(rising & triggers.line == lines(k));
            labels{k} = sprintf('Ch %d: %d TTL', lines(k), numel(times));
            intervals = diff(times);
            intervals = intervals(isfinite(intervals) & intervals > 0);
            if ~isempty(intervals)
                labels{k} = sprintf('%s, %.3g Hz', labels{k}, 1/median(intervals));
            end
        end
        [idx, ok] = listdlg('PromptString', 'Select camera TTL line:', ...
            'ListString', labels, 'SelectionMode', 'single', 'ListSize', [340 200]);
        if ~ok, lines = []; else, lines = lines(idx); end
    end
    if ~isempty(lines)
        data.trigger.time = triggers.timestamp(rising & triggers.line == lines(1)) ...
            - recording.metadata.startTimestamp;
    end
end

% get time sample
data.t = recording.timestamps(:) - recording.metadata.startTimestamp;

% save files
data.files = files;
end



function idx = choose(labels,prompt)
if isempty(labels), error('EMG:emptyRecording','No recording sources found.'); end
idx = 1;
if numel(labels)>1
    [idx,ok] = listdlg('PromptString',prompt,'ListString',labels, ...
        'SelectionMode','single','ListSize',[380 200]);
    if ~ok, error('EMG:cancelled','Recording selection cancelled.'); end
end
end
