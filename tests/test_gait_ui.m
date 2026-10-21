function tests = test_gait_ui
% Desktop integration tests: require MATLAB graphics and Signal Processing Toolbox.
tests = functiontests(localfunctions);
end

function testSwitchingPawsAndTracesRecalculates(testCase)
assumeTrue(testCase, usejava('desktop'), 'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running UI tests.');
S.frameRate = 20;
GAIT.gait_viewer();
cleanup = onCleanup(@()shared.exit_all(false));
hd = S.gait.hd;
hd.pawList.Items = {'a','b'};
hd.pawList.ItemsData = [1 2];
hd.pawList.Value = 1;
hd.pawList.Enable = 'on';
hd.stepList.Items = {'rising','falling','onset','offset','peak','valley'};
hd.stepList.ItemsData = hd.stepList.Items;
hd.stepList.Value = 'rising'; hd.stepList.Enable = 'on';
hd.stepCheck.Enable = 'on';
x = repmat([0;0;4;4;0;0],20,1);
for k = 1:2
    S.gait.paw(k).name = hd.pawList.Items{k};
    S.gait.paw(k).raw_x = x+(k-1)*10;
    S.gait.paw(k).raw_y = circshift(x,1)+(k-1)*20;
    S.gait.paw(k).thresh = struct('x',NaN,'y',NaN,'speed',NaN);
end
notify(S,'InfoChanged');   % gait recalculates on a time-base change
verifyTrue(testCase,S.gait.stepsValid);
first = S.gait.paw(1).rising;
% Other viewers read steps through GAIT.current_steps, never gait's controls.
steps = GAIT.current_steps(S);
verifyEqual(testCase,steps.idx,first(:));
verifyEqual(testCase,steps.t,S.gait.t(first(:)));
verifyEqual(testCase,steps.x,S.gait.paw(1).raw_x(first(:)));
hd.stepCheck.Value = false;
callback = hd.stepCheck.ValueChangedFcn; callback(hd.stepCheck,[]);
verifyEmpty(testCase,GAIT.current_steps(S));
hd.stepCheck.Value = true;
callback(hd.stepCheck,[]);
verifyNotEmpty(testCase,GAIT.current_steps(S));
% Mask GUI must work with the new data model (no per-paw .trace).
verifyFalse(testCase,isfield(S.gait.paw,'trace'));
maskFig = GAIT.mask_GUI([100 100]);
maskCleanup = onCleanup(@()delete(maskFig)); % not stored in hd: exit_all misses it
preview = findall(maskFig,'Type','uibutton','Text','Preview');
callback = preview.ButtonPushedFcn; callback(preview,[]);
verifyTrue(testCase,isfield(S.gait,'maskTemp'));
verifyEqual(testCase,S.gait.paw(1).rising,first);
commit = findall(maskFig,'Type','uibutton','Text','Generate Mask');
callback = commit.ButtonPushedFcn; callback(commit,[]);
verifyFalse(testCase,isfield(S.gait,'maskTemp'));
verifyTrue(testCase,all(S.gait.mask));
hd.pawList.Value = 2;
callback = hd.pawList.ValueChangedFcn; callback(hd.pawList,[]);
verifyEqual(testCase,S.gait.paw(2).rising,first);
hd.trace.Value = 'Y';
callback = hd.trace.ValueChangedFcn; callback(hd.trace,[]);
verifyEqual(testCase,S.gait.paw(2).traceType,'y');
verifyFalse(testCase,any(ismember({'onset','offset'},hd.stepList.Items)));
verifyEmpty(testCase,S.gait.paw(2).onset);
verifyEmpty(testCase,S.gait.paw(2).offset);
verifyNotEqual(testCase,S.gait.paw(2).rising,first);
% Preview never changes committed-mask events, even when it excludes everything.
beforePreview = S.gait.paw(2).rising;
S.gait.maskTemp = false(size(S.gait.t));
notify(S,'MaskPreviewChanged');
verifyEqual(testCase,S.gait.paw(2).rising,beforePreview);
S.gait = rmfield(S.gait,'maskTemp');
% Manual threshold survives refresh and preview.
hd.pawthresh.Value = 99;
callback = hd.pawthresh.ValueChangedFcn; callback(hd.pawthresh,[]);
S.gait.maskTemp = false(size(S.gait.t));
notify(S,'InfoChanged');
verifyEqual(testCase,S.gait.paw(2).thresh.y,99);
verifyEmpty(testCase,S.gait.paw(2).rising);
S.gait = rmfield(S.gait,'maskTemp');
% Commit an all-false mask: calculation succeeds and every marker disappears.
S.gait.mask = false(size(S.gait.t));
notify(S,'MaskChanged');
verifyTrue(testCase,S.gait.stepsValid);
verifyEmpty(testCase,S.gait.paw(2).rising);
verifyEqual(testCase,hd.stepNum.Value,0);
% A failed calculation invalidates stored events and cannot expose old markers.
S.gait.mask = true(numel(S.gait.t)+1,1);
callback = hd.pawList.ValueChangedFcn;
verifyError(testCase,@()callback(hd.pawList,[]),'GAIT:maskSize');
verifyFalse(testCase,GAIT.steps_current(S));
verifyEmpty(testCase,GAIT.current_steps(S));
end

function testEmgInfoPreservesMappedChannelIdentity(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
EMG.emg_viewer();
cleanup = onCleanup(@()shared.exit_all(false));
hd = S.emg.hd;
S.emg.analog_data = zeros(101,2);
S.emg.analog_channels = {'raw1','raw2'};
S.emg.t = (0:0.01:1)'; S.emg.sample_rate = 100; S.emg.display_name = pwd;
S.emg.ch_mapping = table({'B';'A'},{'mapped1';'mapped2'},'VariableNames',{'Muscle','Names'});
hd.sortby.Items = {'Muscle'}; hd.sortby.Value = 'Muscle';
hd.chanList.Items = {'raw1','raw2'}; hd.chanList.ItemsData = [1 2]; hd.chanList.Value = 1;
notify(S,'InfoChanged');
verifyEqual(testCase,hd.chanList.Items(:),{'mapped2';'mapped1'});
verifyEqual(testCase,hd.chanList.Value,1);
S.frameRate = 120; notify(S,'InfoChanged');
verifyEqual(testCase,hd.chanList.Items(:),{'mapped2';'mapped1'});
verifyEqual(testCase,hd.chanList.ItemsData(:),[2;1]);
verifyEqual(testCase,hd.chanList.Value,1);
end

function testRefreshWithoutDataIsSafe(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
figures = {EMG.emg_viewer(), DLC.dlc_viewer(), GAIT.gait_viewer()};
cleanup = onCleanup(@()shared.exit_all(false));
for k = 1:numel(figures)
    button = findall(figures{k},'Tooltip','Refresh');
    callback = button.ButtonPushedFcn; callback(button,[]);
end
verifyTrue(testCase,all(cellfun(@isgraphics,figures)));
end

function testWindowMenuAndExitAll(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
cleanup = onCleanup(@()shared.exit_all(false));
launcher = StepSync(pwd);
verifyEqual(testCase,S.defaultPath,pwd);
dlcFig = shared.open_module('DLC');
verifyFalse(testCase,isgraphics(launcher));   % opening a module closes the launcher
gaitFig = shared.open_module('gait');
verifyEqual(testCase,shared.open_module('dlc'),dlcFig);   % no second window
windowMenu = findall(gaitFig,'Type','uimenu','Text','Window');
items = flip(windowMenu.Children);
verifyEqual(testCase,{items.Text},{'Video','EMG','DLC','Gait','Open All','Bring All to Front'});
verifyEqual(testCase,logical([items(1:4).Checked]),[false false true true]);
verifyEqual(testCase,{items(1:5).Accelerator},{'V','E','D','G','A'});
fileMenu = findall(gaitFig,'Type','uimenu','Text','File');
fileItems = flip(fileMenu.Children);
shortcuts = containers.Map({fileItems.Text},{fileItems.Accelerator});
verifyEqual(testCase,{shortcuts('Open'),shortcuts('Save'),shortcuts('Close')},{'O','S','W'});
% a sub-window is listed, checked, below its module, and removed when closed
S.gait.hd.maskFig = uifigure('Name','Edit Mask');
notify(S,'WindowsChanged');
items = flip(windowMenu.Children);
verifyEqual(testCase,strtrim(strrep(items(5).Text,char(160),' ')),'Edit Mask');
verifyTrue(testCase,logical(items(5).Checked));
delete(S.gait.hd.maskFig);
notify(S,'WindowsChanged');
verifyNumElements(testCase,windowMenu.Children,6);
% Open All opens the missing modules and keeps the open ones
openAll = findall(windowMenu,'Text','Open All');
callback = openAll.MenuSelectedFcn; callback(openAll,[]);
verifyEqual(testCase,sort(fieldnames(S.fig))',{'dlc','emg','gait','video'});
verifyEqual(testCase,S.fig.dlc,dlcFig);
% Exit all closes everything and resets the session
S.frameRate = 30;
shared.exit_all(false);
verifyFalse(testCase,isvalid(S));
verifyFalse(testCase,isgraphics(dlcFig) || isgraphics(gaitFig));
verifyEmpty(testCase,findall(groot,'Type','figure','Name','Video Viewer'));
verifyEqual(testCase,shared.SessionData.instance().frameRate,0);
end
