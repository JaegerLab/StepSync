function tests = test_analysis
% Run from repository root: results = runtests('tests'); assertSuccess(results)
tests = functiontests(localfunctions);
end

function testOnsetAndOffsetStayInsideTrace(testCase)
trace = [0;0;4;4;0];
s = gait.detect_steps(trace, true(size(trace)), 3, 10, 2.5);
verifyEqual(testCase, s.onset, 2);
verifyEqual(testCase, s.offset, 5);
end

function testMaskDoesNotBridgeEvents(testCase)
trace = [0;0;4;4;0;0;4;4;0];
mask = true(size(trace)); mask(2:6) = false;
s = gait.detect_steps(trace, mask, 3, 4);
verifyEmpty(testCase, s.rising); % frame 6 is masked: no crossing allowed
end

function testAllFalseMaskHasNoEvents(testCase)
s = gait.detect_steps([0;4;0;4;0], false(5,1), 2, 2);
for name = {'rising','falling','onset','offset','peak','valley'}
    verifyEmpty(testCase, s.(name{1}));
end
end

function testIndependentPawThresholds(testCase)
a = gait.detect_steps([0;0;4;4;0], true(5,1), 2, 2);
b = gait.detect_steps([10;10;14;14;10], true(5,1), 12, 2);
verifyEqual(testCase, a.rising, b.rising);
verifyEqual(testCase, a.falling, b.falling);
end

function testStaTimeOriginAndDuplicates(testCase)
t = (10:0.01:11)';
signal = zeros(size(t)); signal(41) = 2; signal(61) = 8;
r = gait.sta(signal, t, [10.4;10.4;10.6], 'method', 'none', 'maxLag', 0.05);
verifyEqual(testCase, r.eventNum, 3);
verifyEqual(testCase, r.y(abs(r.t)<1e-9), 4, 'AbsTol', 1e-10);
end

function testStaConstantSignalAtRecordingEdges(testCase)
t = (0:0.01:1)';
r = gait.sta(7*ones(size(t)), t, [0;1], 'method', 'none', 'maxLag', 0.1);
verifyEqual(testCase, r.y, 7*ones(size(r.y)), 'AbsTol', 1e-10);
end

function testStaRejectsEmptyEventsAndGaps(testCase)
t = (0:0.01:1)';
verifyError(testCase, @()gait.sta(ones(size(t)), t, [], 'method','none'), 'gait:sta:noEvents');
t(51:end) = t(51:end)+1;
verifyError(testCase, @()gait.sta(ones(size(t)), t, 0.3, 'method','none'), 'gait:sta:timebase');
end

function testRepeatedControlsPreserveConstantSignal(testCase)
t = (0:0.01:1)';
for method = {'random_time','isi_shuffle','dither'}
    rng(17);
    r = gait.sta(3*ones(size(t)), t, [0;0.4;0.4;1], ...
        'method',method{1}, 'nRep',3, 'maxLag',0.1, 'offset',0.05);
    verifyEqual(testCase, r.randomMean, 3*ones(size(r.t)), 'AbsTol',1e-10);
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

function testSmoothingMissingSamplesDoesNotPoisonTail(testCase)
x = (1:30)'; x(5) = NaN;
y = shared.fastsmooth(x,3);
verifyTrue(testCase,all(isfinite(y(10:end))));
end
