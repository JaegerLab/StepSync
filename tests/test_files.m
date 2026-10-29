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
pose.save_csv(file, poseTable(4));
t = pose.read_csv(file);
verifyEqual(testCase, t.Properties.CustomProperties.FrameIndex, (1:4)');
[aligned, how] = pose.align_frames(t, 10);
verifyEqual(testCase, how, 'as is');
verifyEqual(testCase, height(aligned), 4);
end

function testCroppedCsvWritesOriginalFrames(testCase)
file = tempFile(testCase, '.csv');
cropped = pose.crop_table(poseTable(10), (0:9)'/10, [0.35 0.62]);   % frames 5..7
verifyEqual(testCase, cropped.paw_x, (5:7)');
pose.save_csv(file, cropped);
lines = splitlines(strtrim(fileread(file)));
verifyTrue(testCase, startsWith(lines{4}, '4,'));   % zero-based index of frame 5
t = pose.read_csv(file);
verifyEqual(testCase, t.Properties.CustomProperties.FrameIndex, (5:7)');
verifyEqual(testCase, t.Properties.CustomProperties.Scorer, 'model');
end

function testAlignCroppedToVideo(testCase)
file = tempFile(testCase, '.csv');
pose.save_csv(file, pose.crop_table(poseTable(10), (0:9)'/10, [0.35 0.62]));
t = pose.read_csv(file);
% a video cropped the same way: shift to frames 1..3
[a, how] = pose.align_frames(t, 3);
verifyEqual(testCase, how, 'shifted');
verifyEqual(testCase, a.paw_x, (5:7)');
verifyEqual(testCase, a.Properties.CustomProperties.FrameIndex, (1:3)');
% a full-length video: pad to its length
[a, how] = pose.align_frames(t, 10);
verifyEqual(testCase, how, 'padded');
verifyEqual(testCase, height(a), 10);
verifyEqual(testCase, a.paw_x(5:7), (5:7)');
verifyTrue(testCase, all(isnan(a.paw_x([1:4 8:10]))));
verifyEqual(testCase, a.Properties.UserData, {'paw'});
verifyEqual(testCase, a.Properties.CustomProperties.Scorer, 'model');
% no video, or one too short: pad to the last frame number
[a, how] = pose.align_frames(t, []);
verifyEqual(testCase, [string(how) height(a)], ["padded" "7"]);
[a, ~] = pose.align_frames(t, 5);
verifyEqual(testCase, height(a), 7);
% the padded table saves full length again
pose.save_csv(file, a);
verifyEqual(testCase, pose.read_csv(file).Properties.CustomProperties.FrameIndex, (1:7)');
end

function testAlignRejectsDuplicateFrames(testCase)
t = poseTable(3);
t = addprop(t, 'FrameIndex', 'table');
t.Properties.CustomProperties.FrameIndex = [2; 2; 3];
verifyError(testCase, @()pose.align_frames(t, []), 'pose:frames:duplicates');
end

function g = sampleGait()
n = 10;
g.paw = struct('name', {'fl', 'fr'}, 'rawX', {(1:n)', (2:n+1)'}, 'rawY', {(1:n)', (3:n+2)'}, ...
    'thresh', {struct('x', 5, 'y', NaN, 'speed', NaN), struct('x', NaN, 'y', NaN, 'speed', 2)}, ...
    'x', {zeros(n,1), zeros(n,1)}, 'rising', {[2 5], 3});   % computed fields are not saved
g.selection = struct('paw', 2, 'trace', 'speed', 'step', 'onset', 'show', true);
g.mask = true(n, 1); g.mask(1) = false;
g.maskParam = struct('Rules', table());
g.sta = struct('ephysType', {'Raw'});
g.source = 'pose_module';
g.filename = 'C:\data\pose.csv';
g.t = (0:n-1)'/10;
g.hd = struct();
end

function testGaitRoundTrip(testCase)
file = tempFile(testCase, '.mat');
g = sampleGait();
gait.save_gait(file, g, struct('resolution', 42, 'minInterval', 0.3), 25);
r = gait.read_gait(file);
verifyEqual(testCase, {r.paw.name}, {'fl', 'fr'});
verifyEqual(testCase, r.paw(2).rawY, g.paw(2).rawY);
verifyEqual(testCase, r.paw(1).thresh.x, 5);
verifyFalse(testCase, any(isfield(r.paw, {'x', 'rising'})));
verifyEqual(testCase, r.selection, g.selection);
verifyEqual(testCase, r.mask, g.mask);
verifyEqual(testCase, [r.resolution r.minInterval r.frameRate], [42 0.3 25]);
verifyEqual(testCase, r.source, 'pose_module');
verifyEqual(testCase, r.filename, 'C:\data\pose.csv');
verifyEqual(testCase, r.sta.ephysType, 'Raw');
verifyEmpty(testCase, r.timeRange);
end

function testGaitZoomWindowKeepsLength(testCase)
file = tempFile(testCase, '.mat');
gait.save_gait(file, sampleGait(), struct('resolution', 30, 'minInterval', 0.2), 25, [0.3 0.6]);
r = gait.read_gait(file);
inside = false(10, 1); inside(4:7) = true;   % t = 0.3 .. 0.6
verifyEqual(testCase, numel(r.paw(1).rawX), 10);
verifyTrue(testCase, all(isnan(r.paw(1).rawX(~inside))));
verifyEqual(testCase, r.paw(1).rawX(inside), (4:7)');
verifyEqual(testCase, r.mask, inside);
verifyEqual(testCase, r.timeRange, [0.3 0.6]);
end

function testGaitRejectsOtherFiles(testCase)
file = tempFile(testCase, '.mat');
x = 1;
save(file, 'x');
verifyError(testCase, @()gait.read_gait(file), 'gait:file:format');
gait.save_gait(file, sampleGait(), struct('resolution', 30, 'minInterval', 0.2), 25);
formatVersion = 3;
save(file, 'formatVersion', '-append');
verifyError(testCase, @()gait.read_gait(file), 'gait:file:newer');
formatVersion = 1;
save(file, 'formatVersion', '-append');
verifyError(testCase, @()gait.read_gait(file), 'gait:file:older');
f = load(file); f.formatVersion = 2; f.gait.mask = true(3, 1);
save(file, '-struct', 'f', '-v7.3');
verifyError(testCase, @()gait.read_gait(file), 'gait:file:format');
f.fileFormat = 'StepSync Ephys'; f.gait.mask = true(10, 1);
save(file, '-struct', 'f', '-v7.3');
verifyError(testCase, @()gait.read_gait(file), 'gait:file:format');
end
