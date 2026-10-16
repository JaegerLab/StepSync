function data = read_ephys(files)
% Read Open Ephys and convert it to Intan compatible format.
% go to https://github.com/open-ephys/open-ephys-matlab-tools
% for ephys reader installation and documentation.

session = Session(files);
data = struct();
if isempty(session.recordNodes); return; end

keys = session.recordNodes{1}.recordings{1}.continuous.keys();
key_name = keys{1};
recording = session.recordNodes{1}.recordings{1}.continuous(key_name);

channel_names = recording.metadata.names;
data.sample_rate = recording.metadata.sampleRate;

% get data from analog channels
analog_chans = startsWith(channel_names, 'CH');
if any(analog_chans)
    data.analog_data = double(recording.samples(analog_chans,:)');
    data.analog_channels = channel_names(analog_chans);
end

% get data from ADC channels
adc_chans = startsWith(channel_names, 'ADC');
if any(adc_chans)
    data.adc_data = double(recording.samples(adc_chans,:)');
end

% get trigger event time
events = session.recordNodes{1}.recordings{1}.ttlEvents;
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


