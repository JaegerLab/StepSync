function tests = test_sessions
% Session file format: write, read back, reject other files. No GUI needed.
tests = functiontests(localfunctions);
end

function setup(testCase)
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running session tests.');
% two module "windows" (plain hidden figures) with DLC data and gait data
S.fig(1).dlc = figure('Visible', 'off', 'Position', [10 20 300 200]);
S.fig.gait = figure('Visible', 'off', 'Position', [30 40 500 400]);
S.dlc(1).table = table((1:5)', (1:5)', ones(5,1), 'VariableNames', {'paw_x','paw_y','paw_likelihood'});
S.dlc.filename = 'C:\data\pose.csv';
S.dlc.hd = struct();
S.gait(1).paw = struct('name', 'paw', 'raw_x', (1:5)', 'raw_y', (1:5)');
S.gait.hd = struct();
S.frameRate = 30; S.currentTime = 1.5; S.currentZoom = [1 2];
S.defaultPath = tempdir;
testCase.TestData.file = [tempname '.mat'];
testCase.TestData.figs = {S.fig.dlc, S.fig.gait};
addTeardown(testCase, @()teardownSession(testCase));
end

function teardownSession(testCase)
cellfun(@delete, testCase.TestData.figs);
if isfile(testCase.TestData.file), delete(testCase.TestData.file); end
delete(shared.SessionData.instance());   % fresh session for the next test
end

function testWriteThenReadKeepsSelectedModules(testCase)
file = testCase.TestData.file;
shared.write_session(file, {'dlc'});
saved = shared.read_session(file);
verifyEqual(testCase, saved.fileFormat, 'StepSync session');
verifyEqual(testCase, saved.formatVersion, 3);
verifyEqual(testCase, [saved.frameRate saved.currentTime saved.currentZoom], [30 1.5 1 2]);
verifyEqual(testCase, fieldnames(saved.figures), {'dlc'});
verifyEqual(testCase, saved.figures.dlc.Position, [10 20 300 200]);
verifyEqual(testCase, saved.dlc.filename, 'C:\data\pose.csv');
verifyEqual(testCase, height(saved.dlc.table), 5);
verifyFalse(testCase, isfield(saved.dlc, 'hd'));
verifyTrue(testCase, isfield(saved.dlc, 'parameters'));
verifyFalse(testCase, isfield(saved, 'gait'));   % not selected
verifyFalse(testCase, any(isfield(saved, {'defaultPath', 'timebaseVersion'})));
end

function testModuleWithoutDataSavesOnlyItsWindow(testCase)
file = testCase.TestData.file;
S = shared.SessionData.instance();
S.gait = struct('hd', struct());   % window open, no paws
shared.write_session(file, {'dlc', 'gait'});
saved = shared.read_session(file);
verifyEqual(testCase, sort(fieldnames(saved.figures)), {'dlc'; 'gait'});
verifyFalse(testCase, isfield(saved, 'gait'));
end

function testRejectsOtherFiles(testCase)
file = testCase.TestData.file;
shared.write_session(file, {'dlc', 'gait'});
good = load(file);
cases = {
    rmfield(good, 'fileFormat'),                    'StepSync:session:format'
    rmfield(good, 'formatVersion'),                 'StepSync:session:format'
    setfield(good, 'fileFormat', 'StepSync EMG'),   'StepSync:session:format' %#ok<SFLD>
    setfield(good, 'formatVersion', 2),             'StepSync:session:older' %#ok<SFLD>
    setfield(good, 'formatVersion', 4),             'StepSync:session:newer' %#ok<SFLD>
    rmfield(good, 'figures'),                       'StepSync:session:format'
    setfield(good, 'currentZoom', [2 1]),           'StepSync:zoom' %#ok<SFLD>
    };
for k = 1:size(cases, 1)
    s = cases{k,1};
    save(file, '-struct', 's', '-v7.3');
    verifyError(testCase, @()shared.read_session(file), cases{k,2}, sprintf('case %d', k));
end
end

function testRejectsSessionBeforeFormatVersion3(testCase)
file = testCase.TestData.file;
% fields of a session saved before format version 3
defaultPath = tempdir; frameRate = 30; currentTime = 0; currentZoom = [0 10];
timebaseVersion = 2; figures = struct('dlc', struct('Position', [1 1 2 2]));
save(file, 'defaultPath', 'frameRate', 'currentTime', 'currentZoom', ...
    'timebaseVersion', 'figures', '-v7.3');
verifyError(testCase, @()shared.read_session(file), 'StepSync:session:format');
end
