function tests = test_emg
% EMG data types and the EMG .mat file. No GUI needed.
tests = functiontests(localfunctions);
end

function emg = sampleEmg()
t = (0:9)'/10;
emg.analog_channels = {'A', 'B'};
emg.trigger = struct('time', (0:0.1:0.5)', 'freq', 10, 'number', 6);
emg.display_name = 'C:\rec';
emg.filename = {'C:\rec\a.rhd'};
emg.hd = struct();
emg.raw = struct('data', [t 2*t], 't', t, 'sample_rate', 10);
emg.processed = struct('data', {t(1:2:end), 3*t(1:2:end)}, 't', {t(1:2:end), t(1:2:end)}, ...
    'sample_rate', {5, 5}, 'parameters', {struct('Source', 'Raw'), struct('Source', 'Processed 1')});
end

function testTypesSourceAndDelete(testCase)
emg = sampleEmg();
verifyEqual(testCase, EMG.emg_types(emg), {'Raw', 'Processed 1', 'Processed 2'});
verifyEqual(testCase, EMG.emg_source(emg, 'Processed 2').parameters.Source, 'Processed 1');
verifyEqual(testCase, EMG.emg_source(emg, 'Raw').sample_rate, 10);
verifyError(testCase, @()EMG.emg_source(emg, 'Processed 3'), 'EMG:type');
emg = EMG.emg_delete(emg, 'Processed 1');   % renumbered
verifyEqual(testCase, EMG.emg_types(emg), {'Raw', 'Processed 1'});
verifyEqual(testCase, EMG.emg_source(emg, 'Processed 1').parameters.Source, 'Processed 1');
emg = EMG.emg_delete(emg, 'Raw');
verifyEqual(testCase, EMG.emg_types(emg), {'Processed 1'});
emg = EMG.emg_delete(emg, 'Processed 1');
verifyEmpty(testCase, EMG.emg_types(emg));
verifyEqual(testCase, emg.trigger.freq, 10);   % metadata kept
end

function testHasEmgNeedsData(testCase)
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running this test.');
addTeardown(testCase, @()delete(shared.SessionData.instance()));
S.emg = sampleEmg();
verifyTrue(testCase, S.has('emg'));
S.emg = EMG.emg_delete(S.emg, 'Raw');
verifyTrue(testCase, S.has('emg'));   % processed only
S.emg.processed(:) = [];
verifyFalse(testCase, S.has('emg'));
verifyEqual(testCase, S.getFrameRate(), 10);   % trigger still drives timing
end

function testSaveThenOpenSelectedTypes(testCase)
file = [tempname '.mat'];
addTeardown(testCase, @()delete(file));
emg = sampleEmg();
EMG.save_emg(file, emg, {'Raw', 'Processed 2'});
vars = who('-file', file);
verifyEqual(testCase, sort(vars), sort({'fileFormat'; 'formatVersion'; 'emg'; 'raw'; 'processed1'}));
meta = load(file, 'emg', 'fileFormat', 'formatVersion');
verifyFalse(testCase, any(isfield(meta.emg, {'hd', 'raw', 'processed', 'temp'})));
verifyEqual(testCase, [string(meta.fileFormat) string(meta.formatVersion)], ["StepSync EMG" "1"]);
[names, bytes] = EMG.emg_file_contents(file);
verifyEqual(testCase, names, {'raw', 'processed1'});
verifyTrue(testCase, all(bytes > 0));
% processed only: no raw in memory
loaded = EMG.load_emg(file, {'processed1'});
verifyEqual(testCase, EMG.emg_types(loaded), {'Processed 1'});
verifyEqual(testCase, loaded.processed(1).data, emg.processed(2).data);
verifyEqual(testCase, loaded.processed(1).parameters.Source, 'Processed 1');
verifyEqual(testCase, loaded.trigger, emg.trigger);
loaded = EMG.load_emg(file, names);
verifyEqual(testCase, EMG.emg_types(loaded), {'Raw', 'Processed 1'});
verifyEqual(testCase, loaded.raw, emg.raw);
end

function testFileContentsSortsAndRejects(testCase)
file = [tempname '.mat'];
addTeardown(testCase, @()delete(file));
fileFormat = 'StepSync EMG'; formatVersion = 1; emg = struct();
p = struct('data', 1, 't', 0, 'sample_rate', 1, 'parameters', struct()); processed10 = p; processed2 = p;
save(file, 'fileFormat', 'formatVersion', 'emg', 'processed10', 'processed2', '-v7.3');
verifyEqual(testCase, EMG.emg_file_contents(file), {'processed2', 'processed10'});
formatVersion = 2;
save(file, 'formatVersion', '-append');
verifyError(testCase, @()EMG.emg_file_contents(file), 'EMG:file:newer');
fileFormat = 'StepSync session'; formatVersion = 1;
save(file, 'fileFormat', 'formatVersion', '-append');
verifyError(testCase, @()EMG.emg_file_contents(file), 'EMG:file:format');
x = 1;
save(file, 'x', '-v7.3');
verifyError(testCase, @()EMG.emg_file_contents(file), 'EMG:file:format');
end

function testTtlChannelsAndLabels(testCase)
t = (0:999)'/1000;   % 1 kHz, 1 s
camera = mod(0:999, 10)' < 2;   % 100 Hz, 2 ms pulses
long = t >= 0.1 & t < 0.9;      % one 0.8 s pulse
ch = EMG.ttl_channels(t, [camera long zeros(1000,1)]);
verifyEqual(testCase, {ch.name}, {'DIN-00', 'DIN-01', 'DIN-02'});
verifyEqual(testCase, ch(1).rise, (0.01:0.01:0.99)', 'AbsTol', 1e-12);   % no edge at sample 1
verifyEqual(testCase, EMG.ttl_stats(ch(1)), 'DIN-00: 99 TTL, 2 ms, 100 Hz');
verifyEqual(testCase, EMG.ttl_stats(ch(2)), 'DIN-01: 1 TTL, 800 ms, - Hz');
verifyEqual(testCase, EMG.ttl_stats(ch(3)), 'DIN-02: 0 TTL, -, - Hz');
ch = EMG.ttl_channels(t, double(t >= 0.5), {'X'});   % no falling edge: no width
verifyEqual(testCase, EMG.ttl_stats(ch), 'X: 1 TTL, -, - Hz');
end

function testFrameRateSourcesAndOverride(testCase)
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running this test.');
addTeardown(testCase, @()delete(shared.SessionData.instance()));
[rate, source] = S.getFrameRate();
verifyEqual(testCase, {rate, source}, {1, 'none'});
S.emg = sampleEmg();   % trigger at 0:0.1:0.5
[rate, source] = S.getFrameRate();
verifyEqual(testCase, {rate, source}, {10, 'trigger'});
verifyEqual(testCase, S.getFrameTimes(6), S.emg.trigger.time);
S.setFrameRate(20);   % a typed-in rate replaces the trigger times
[rate, source] = S.getFrameRate();
verifyEqual(testCase, {rate, source}, {20, 'manual'});
verifyEqual(testCase, S.getFrameTimes(3), (1:3)'/20);
S.setFrameRate([]);   % cleared: automatic again
verifyEqual(testCase, S.frameRate, 0);
verifyEqual(testCase, S.getFrameTimes(6), S.emg.trigger.time);
S.setFrameRate(0);
verifyEqual(testCase, S.frameRate, 0);
verifyError(testCase, @()S.setFrameRate(-1), 'MATLAB:expectedNonnegative');
end

function testPrepDownSamplesOnExactGrid(testCase)
t = (-0.5:0.001:2.9995)';   % starts before 0, ends between grid points
x = randn(numel(t), 1);
[y, newT] = EMG.emg_prep(x, t, struct('Rectify', true, 'DownSampleRate', 300), 1000);
verifyEqual(testCase, newT, (0:899)'/300, 'AbsTol', 1e-12);   % exactly 300 Hz from 0
verifyEqual(testCase, size(y), [900 1]);
verifyFalse(testCase, any(isnan(y)));
[y, newT] = EMG.emg_prep(x, t, struct('Rectify', true), 1000);
verifyEqual(testCase, newT, t(t>=0));
verifyEqual(testCase, y, abs(x(t>=0)));
end

function testPrepFilterTypes(testCase)
fs = 1000;
t = (0:9999)'/fs;
lowTone = sin(2*pi*10*t); midTone = sin(2*pi*100*t); highTone = sin(2*pi*400*t);
x = lowTone + midTone + highTone;
keep = t > 1;   % skip the filter transient
power = @(y, tone) abs(mean(y(keep) .* tone(keep)));
band = struct('HighPassFreq', 50, 'LowPassFreq', 200, 'FiltFilt', true);
y = EMG.emg_prep(x, t, setfield(band, 'FilterType', 'bandpass'), fs);
verifyGreaterThan(testCase, power(y, midTone), 10 * power(y, lowTone));
verifyGreaterThan(testCase, power(y, midTone), 10 * power(y, highTone));
y = EMG.emg_prep(x, t, setfield(band, 'FilterType', 'bandstop'), fs);
verifyGreaterThan(testCase, power(y, lowTone), 10 * power(y, midTone));
verifyGreaterThan(testCase, power(y, highTone), 10 * power(y, midTone));
y = EMG.emg_prep(x, t, struct('FilterType', 'lowpass', 'LowPassFreq', 50), fs);
verifyGreaterThan(testCase, power(y, lowTone), 10 * power(y, highTone));
y = EMG.emg_prep(x, t, struct('HighPassFreq', 200), fs);   % old parameters: high pass
verifyGreaterThan(testCase, power(y, highTone), 10 * power(y, lowTone));
end

function testSaveZoomWindowKeepsTimes(testCase)
file = [tempname '.mat'];
addTeardown(testCase, @()delete(file));
emg = sampleEmg();
EMG.save_emg(file, emg, {'Raw', 'Processed 1'}, [0.2 0.5]);
f = load(file);
verifyEqual(testCase, f.raw.t, (2:5)'/10, 'AbsTol', 1e-12);   % absolute times, not shifted
verifyEqual(testCase, f.raw.data, emg.raw.data(3:6, :));
verifyEqual(testCase, f.processed1.t, [0.2; 0.4], 'AbsTol', 1e-12);
verifyEqual(testCase, f.emg.time_range, [0.2 0.5]);
verifyEqual(testCase, f.emg.trigger, emg.trigger);   % metadata unchanged
EMG.save_emg(file, emg, {'Raw'});
f = load(file);
verifyEqual(testCase, f.raw, emg.raw);
verifyEmpty(testCase, f.emg.time_range);
end