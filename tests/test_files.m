function tests = test_files
% DLC csv frame numbers and cropping; the gait .mat file. No GUI needed.
tests = functiontests(localfunctions);
end

function t = poseTable(n)
t = table((1:n)', (11:10+n)', ones(n,1), 'VariableNames', {'paw_x','paw_y','paw_likelihood'});
t.Properties.UserData = {'paw'};
t = addprop(t, 'Scorer', 'table'); t.Properties.CustomProperties.Scorer = 'model';
end

function file = tempFile(testCase, ext)
file = [tempname ext];
addTeardown(testCase, @()deleteIfExists(file));
end

function deleteIfExists(file)
if isfile(file), delete(file); end
end

function testFullCsvKeepsFrameNumbers(testCase)
file = tempFile(testCase, '.csv');
DLC.save_csv(file, poseTable(4));
t = DLC.read_csv(file);
verifyEqual(testCase, t.Properties.CustomProperties.FrameIndex, (1:4)');
[aligned, how] = DLC.align_frames(t, 10);
verifyEqual(testCase, how, 'as is');
verifyEqual(testCase, height(aligned), 4);
end

function testCroppedCsvWritesOriginalFrames(testCase)
file = tempFile(testCase, '.csv');
cropped = DLC.crop_table(poseTable(10), (0:9)'/10, [0.35 0.62]);   % frames 5..7
verifyEqual(testCase, cropped.paw_x, (5:7)');
DLC.save_csv(file, cropped);
lines = splitlines(strtrim(fileread(file)));
verifyTrue(testCase, startsWith(lines{4}, '4,'));   % zero-based index of frame 5
t = DLC.read_csv(file);
verifyEqual(testCase, t.Properties.CustomProperties.FrameIndex, (5:7)');
verifyEqual(testCase, t.Properties.CustomProperties.Scorer, 'model');
end

function testAlignCroppedToVideo(testCase)
file = tempFile(testCase, '.csv');
DLC.save_csv(file, DLC.crop_table(poseTable(10), (0:9)'/10, [0.35 0.62]));
t = DLC.read_csv(file);
% a video cropped the same way: shift to frames 1..3
[a, how] = DLC.align_frames(t, 3);
verifyEqual(testCase, how, 'shifted');
verifyEqual(testCase, a.paw_x, (5:7)');
verifyEqual(testCase, a.Properties.CustomProperties.FrameIndex, (1:3)');
% a full-length video: pad to its length
[a, how] = DLC.align_frames(t, 10);
verifyEqual(testCase, how, 'padded');
verifyEqual(testCase, height(a), 10);
verifyEqual(testCase, a.paw_x(5:7), (5:7)');
verifyTrue(testCase, all(isnan(a.paw_x([1:4 8:10]))));
verifyEqual(testCase, a.Properties.UserData, {'paw'});
verifyEqual(testCase, a.Properties.CustomProperties.Scorer, 'model');
% no video, or one too short: pad to the last frame number
[a, how] = DLC.align_frames(t, []);
verifyEqual(testCase, [string(how) height(a)], ["padded" "7"]);
[a, ~] = DLC.align_frames(t, 5);
verifyEqual(testCase, height(a), 7);
% the padded table saves full length again
DLC.save_csv(file, a);
verifyEqual(testCase, DLC.read_csv(file).Properties.CustomProperties.FrameIndex, (1:7)');
end

function testAlignRejectsDuplicateFrames(testCase)
t = poseTable(3);
t = addprop(t, 'FrameIndex', 'table');
t.Properties.CustomProperties.FrameIndex = [2; 2; 3];
verifyError(testCase, @()DLC.align_frames(t, []), 'DLC:frames:duplicates');
end

function g = sampleGait()
n = 10;
g.paw = struct('name', {'fl', 'fr'}, 'raw_x', {(1:n)', (2:n+1)'}, 'raw_y', {(1:n)', (3:n+2)'}, ...
    'thresh', {struct('x', 5, 'y', NaN, 'speed', NaN), struct('x', NaN, 'y', NaN, 'speed', 2)}, ...
    'x', {zeros(n,1), zeros(n,1)}, 'rising', {[2 5], 3});   % computed fields are not saved
g.selection = struct('paw', 2, 'trace', 'speed', 'step', 'onset', 'show', true);
g.mask = true(n, 1); g.mask(1) = false;
g.maskParam = struct('Rules', table());
g.sta = struct('emgType', {'Raw'});
g.source = 'dlc_module';
g.filename = 'C:\data\pose.csv';
g.t = (0:n-1)'/10;
g.hd = struct();
end

function testGaitRoundTrip(testCase)
file = tempFile(testCase, '.mat');
g = sampleGait();
GAIT.save_gait(file, g, struct('resolution', 42, 'minInterval', 0.3), 25);
r = GAIT.read_gait(file);
verifyEqual(testCase, {r.paw.name}, {'fl', 'fr'});
verifyEqual(testCase, r.paw(2).raw_y, g.paw(2).raw_y);
verifyEqual(testCase, r.paw(1).thresh.x, 5);
verifyFalse(testCase, any(isfield(r.paw, {'x', 'rising'})));
verifyEqual(testCase, r.selection, g.selection);
verifyEqual(testCase, r.mask, g.mask);
verifyEqual(testCase, [r.resolution r.minInterval r.frameRate], [42 0.3 25]);
verifyEqual(testCase, r.source, 'dlc_module');
verifyEqual(testCase, r.filename, 'C:\data\pose.csv');
verifyEqual(testCase, r.sta.emgType, 'Raw');
verifyEmpty(testCase, r.time_range);
end

function testGaitZoomWindowKeepsLength(testCase)
file = tempFile(testCase, '.mat');
GAIT.save_gait(file, sampleGait(), struct('resolution', 30, 'minInterval', 0.2), 25, [0.3 0.6]);
r = GAIT.read_gait(file);
inside = false(10, 1); inside(4:7) = true;   % t = 0.3 .. 0.6
verifyEqual(testCase, numel(r.paw(1).raw_x), 10);
verifyTrue(testCase, all(isnan(r.paw(1).raw_x(~inside))));
verifyEqual(testCase, r.paw(1).raw_x(inside), (4:7)');
verifyEqual(testCase, r.mask, inside);
verifyEqual(testCase, r.time_range, [0.3 0.6]);
end

function testGaitRejectsOtherFiles(testCase)
file = tempFile(testCase, '.mat');
x = 1;
save(file, 'x');
verifyError(testCase, @()GAIT.read_gait(file), 'GAIT:file:format');
GAIT.save_gait(file, sampleGait(), struct('resolution', 30, 'minInterval', 0.2), 25);
formatVersion = 2;
save(file, 'formatVersion', '-append');
verifyError(testCase, @()GAIT.read_gait(file), 'GAIT:file:newer');
f = load(file); f.formatVersion = 1; f.gait.mask = true(3, 1);
save(file, '-struct', 'f', '-v7.3');
verifyError(testCase, @()GAIT.read_gait(file), 'GAIT:file:format');
f.fileFormat = 'StepSync EMG'; f.gait.mask = true(10, 1);
save(file, '-struct', 'f', '-v7.3');
verifyError(testCase, @()GAIT.read_gait(file), 'GAIT:file:format');
end
