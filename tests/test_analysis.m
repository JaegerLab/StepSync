function tests = test_analysis
% Run from repository root: results = runtests('tests'); assertSuccess(results)
tests = functiontests(localfunctions);
end

function testOnsetAndOffsetStayInsideTrace(testCase)
trace = [0;0;4;4;0];
s = GAIT.detect_steps(trace, true(size(trace)), 3, 10);
verifyEqual(testCase, s.onset, 2);
verifyEqual(testCase, s.offset, 5);
end

function testMaskDoesNotBridgeEvents(testCase)
trace = [0;0;4;4;0;0;4;4;0];
mask = true(size(trace)); mask(2:6) = false;
s = GAIT.detect_steps(trace, mask, 3, 4);
verifyEmpty(testCase, s.rising); % frame 6 is masked: no crossing allowed
end

function testAllFalseMaskHasNoEvents(testCase)
s = GAIT.detect_steps([0;4;0;4;0], false(5,1), 2, 2);
for name = {'rising','falling','onset','offset','peak','valley'}
    verifyEmpty(testCase, s.(name{1}));
end
end

function testIndependentPawThresholds(testCase)
a = GAIT.detect_steps([0;0;4;4;0], true(5,1), 2, 2);
b = GAIT.detect_steps([10;10;14;14;10], true(5,1), 12, 2);
verifyEqual(testCase, a.rising, b.rising);
verifyEqual(testCase, a.falling, b.falling);
end

function testStaTimeOriginAndDuplicates(testCase)
t = (10:0.01:11)';
emg = zeros(size(t)); emg(41) = 2; emg(61) = 8;
r = GAIT.sta(emg, t, [10.4;10.4;10.6], 'method', 'none', 'max_lag', 0.05);
verifyEqual(testCase, r.eventNum, 3);
verifyEqual(testCase, r.y(abs(r.t)<1e-9), 4, 'AbsTol', 1e-10);
end

function testStaConstantSignalAtRecordingEdges(testCase)
t = (0:0.01:1)';
r = GAIT.sta(7*ones(size(t)), t, [0;1], 'method', 'none', 'max_lag', 0.1);
verifyEqual(testCase, r.y, 7*ones(size(r.y)), 'AbsTol', 1e-10);
end

function testStaRejectsEmptyEventsAndGaps(testCase)
t = (0:0.01:1)';
verifyError(testCase, @()GAIT.sta(ones(size(t)), t, [], 'method','none'), 'GAIT:sta:noEvents');
t(51:end) = t(51:end)+1;
verifyError(testCase, @()GAIT.sta(ones(size(t)), t, 0.3, 'method','none'), 'GAIT:sta:timebase');
end

function testRepeatedControlsPreserveConstantSignal(testCase)
t = (0:0.01:1)';
for method = {'random_time','isi_shuffle','dither'}
    rng(17);
    r = GAIT.sta(3*ones(size(t)), t, [0;0.4;0.4;1], ...
        'method',method{1}, 'nRep',3, 'max_lag',0.1, 'offset',0.05);
    verifyEqual(testCase, r.random_mean, 3*ones(size(r.t)), 'AbsTol',1e-10);
end
end

function testSmoothingFullAndOversizedWindows(testCase)
x = (1:5)';
for w = [1 5 20]
    actual = shared.fastsmooth(x,w);
    verifySize(testCase,actual,size(x));
    verifyTrue(testCase,all(isfinite(actual)));
end
verifyEqual(testCase,shared.fastsmooth(x,1),x);
end

function testSparseSleapRetainsFrameIndices(testCase)
filename = [tempname '.analysis.csv'];
cleanup = onCleanup(@()delete(filename)); %#ok<NASGU>
raw = table([0;2], [1;3], [2;4], [0.9;0.8], ...
    'VariableNames',{'frame_idx','paw_x','paw_y','paw_score'});
writetable(raw,filename);
t = DLC.read_slp(filename);
verifyEqual(testCase,height(t),3);
verifyTrue(testCase,all(isnan(t{2,:})));
verifyEqual(testCase,t.paw_x([1 3]),[1;3]);
verifyEqual(testCase,t.Properties.UserData,{'paw'});
end


function testSmoothingMissingSamplesDoesNotPoisonTail(testCase)
x = (1:30)'; x(5) = NaN;
y = shared.fastsmooth(x,3);
verifyTrue(testCase,all(isfinite(y(10:end))));
end
