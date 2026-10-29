function tests = test_windows
% Window management without graphics: placement and session reset.
tests = functiontests(localfunctions);
end

function testPlaceWindowStaysOnMonitorUnderCursor(testCase)
monitors = [1 1 1920 1080; 1921 1 1280 1024];
% past the right and top edge of the second monitor
pos = shared.place_window([3100 1000 400 300], 0, [3150 1000], monitors);
verifyEqual(testCase, pos, [1921+1280-400, 1+1024-300-32, 400, 300]);
% left of the first monitor, below its bottom edge
pos = shared.place_window([-50 -80 400 300], 0, [10 10], monitors);
verifyEqual(testCase, pos, [1 1 400 300]);
% a menu bar lowers the highest allowed position
pos = shared.place_window([100 1000 400 300], 22, [100 1000], monitors);
verifyEqual(testCase, pos(2), 1+1080-300-32-22);
% inside: unchanged
verifyEqual(testCase, shared.place_window([100 100 400 300], 0, [150 150], monitors), [100 100 400 300]);
end

function testPlaceWindowKeepsTopLeftOfLargeWindow(testCase)
monitors = [1 1 800 600];
pos = shared.place_window([300 300 1000 900], 0, [10 10], monitors);
verifyEqual(testCase, pos(1), 1);
verifyEqual(testCase, pos(2) + 900 + 32, 601);   % top edge on the monitor's top
end

function testPlaceWindowUsesNearestMonitorOutsideAll(testCase)
monitors = [1 1 1920 1080; 1921 1 1280 1024];
pos = shared.place_window([5000 100 400 300], 0, [5000 100], monitors);
verifyEqual(testCase, pos(1), 1921+1280-400);
end

function testClosingLastModuleResetsSession(testCase)
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running this test.');
S.frameRate = 25;
S.closingAll = true;
S.moduleClosed();   % all windows closing: no reset yet
verifyTrue(testCase, isvalid(S));
S.closingAll = false;
S.moduleClosed();
verifyFalse(testCase, isvalid(S));
verifyEqual(testCase, shared.SessionData.instance().frameRate, 0);
end

function testCloseWithoutDataDoesNotAsk(testCase)
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running this test.');
for module = {'video', 'ephys', 'pose', 'gait'}
    % no figure: asking would error
    verifyTrue(testCase, shared.confirm_close([], module{1}), module{1});
end
end

function testToolWarningStaysOffUntilLastModuleCloses(testCase)
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running this test.');
id = 'MATLAB:modes:mode:InvalidPropertySet';
delete(S);   % the next session starts from the state set here
old = warning('query', id);
restore = onCleanup(@()warning(old));
warning('on', id);
S = shared.SessionData.instance();
verifyEqual(testCase, warning('query', id).state, 'off');
% another module window still open: closing one keeps the session and the warning off
other = figure('Visible', 'off');
closeOther = onCleanup(@()delete(other));
S.fig(1).gait = other;
S.moduleClosed();
verifyTrue(testCase, isvalid(S));
verifyEqual(testCase, warning('query', id).state, 'off');
% last one closed: the session ends and the warning is back
delete(other);
S.moduleClosed();
verifyFalse(testCase, isvalid(S));
verifyEqual(testCase, warning('query', id).state, 'on');
end

function testRememberPathKeepsFolder(testCase)
S = shared.SessionData.instance();
S.rememberPath(fullfile(tempdir, 'missing_file.csv'));
verifyEqual(testCase, S.defaultPath, fileparts(fullfile(tempdir, 'x')));
S.rememberPath(fullfile(tempdir, 'no_such_folder', 'file.csv'));   % ignored
verifyEqual(testCase, S.defaultPath, fileparts(fullfile(tempdir, 'x')));
end

function keepPositionPrefs(testCase)
% the tests below change the saved window positions; put the user's back
had = ispref('StepSync', 'windowPositions');
if had, old = getpref('StepSync', 'windowPositions'); else, old = []; end
addTeardown(testCase, @()restorePositionPrefs(had, old));
if had, rmpref('StepSync', 'windowPositions'); end
end

function restorePositionPrefs(had, old)
if had
    setpref('StepSync', 'windowPositions', old);
elseif ispref('StepSync', 'windowPositions')
    rmpref('StepSync', 'windowPositions');
end
end

function testWindowPositionRemembered(testCase)
keepPositionPrefs(testCase);
monitors = [1 1 1920 1080; 1921 1 1280 1024];
default = [100 100 1000 500];
verifyEqual(testCase, shared.window_position('pose', default, monitors), default);
fig = figure('Visible', 'off', 'Position', [2100 300 800 400]);
addTeardown(testCase, @()delete(fig));
shared.remember_position('pose', fig);
verifyEqual(testCase, shared.window_position('pose', default, monitors), [2100 300 800 400]);
verifyEqual(testCase, shared.window_position('gait', default, monitors), default);
% second monitor gone: moved onto the remaining one
verifyEqual(testCase, shared.window_position('pose', default, monitors(1,:)), ...
    [1920-800+1, 300, 800, 400]);
end

function testWindowPositionIgnoresBadPrefs(testCase)
keepPositionPrefs(testCase);
default = [100 100 1000 500];
setpref('StepSync', 'windowPositions', 'junk');
verifyEqual(testCase, shared.window_position('ephys', default), default);
setpref('StepSync', 'windowPositions', struct('ephys', [1 2 0 5]));
verifyEqual(testCase, shared.window_position('ephys', default), default);
fig = figure('Visible', 'off', 'Position', [200 200 600 300]);
addTeardown(testCase, @()delete(fig));
shared.remember_position('ephys', fig);   % replaces the junk entry
verifyEqual(testCase, shared.window_position('ephys', default, [1 1 1920 1080]), [200 200 600 300]);
end
