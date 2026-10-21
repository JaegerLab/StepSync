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

function testPrepReportsAchievedRate(testCase)
t = (0:2999)'/1000;
x = randn(numel(t), 1);
[~, newT, fs] = EMG.emg_prep(x, t, struct('Rectify', true, 'DownSampleRate', 300), 1000);
verifyEqual(testCase, fs, 1000/3, 'AbsTol', 1e-12);
verifyEqual(testCase, numel(newT), 1000);
[~, ~, fs] = EMG.emg_prep(x, t, struct('Rectify', true), 1000);
verifyEqual(testCase, fs, 1000);
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