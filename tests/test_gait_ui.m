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
S.emg.raw = struct('data',zeros(101,2),'t',(0:0.01:1)','sample_rate',100);
S.emg.analog_channels = {'raw1','raw2'};
S.emg.display_name = pwd;
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
windowMenu = findall(gaitFig,'Type','uimenu','Tag','Window');
items = flip(windowMenu.Children);
verifyEqual(testCase,{items.Text},{'Video','EMG','DLC','Gait','Open All','Bring All to Front'});
verifyEqual(testCase,logical([items(1:4).Checked]),[false false true true]);
verifyEqual(testCase,{items(1:5).Accelerator},{'V','E','D','G','A'});
fileMenu = findall(gaitFig,'Type','uimenu','Tag','File');
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

function testSessionRestoreReplacesWindows(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
cleanup = onCleanup(@()shared.exit_all(false));
file = [tempname '.mat'];
removeFile = onCleanup(@()delete(file));
S.frameRate = 20;
gaitFig = GAIT.gait_viewer();
dlcFig = DLC.dlc_viewer();
hd = S.gait.hd;
hd.pawList.Items = {'a','b'}; hd.pawList.ItemsData = [1 2]; hd.pawList.Value = 2;
hd.pawList.Enable = 'on';
hd.stepList.Items = {'rising','falling','onset','offset','peak','valley'};
hd.stepList.ItemsData = hd.stepList.Items;
hd.stepList.Value = 'rising'; hd.stepList.Enable = 'on';
hd.resolution.Value = 42;
x = repmat([0;0;4;4;0;0],20,1);
for k = 1:2
    S.gait.paw(k).name = hd.pawList.Items{k};
    S.gait.paw(k).raw_x = x+(k-1)*10;
    S.gait.paw(k).raw_y = circshift(x,1)+(k-1)*20;
    S.gait.paw(k).thresh = struct('x',NaN,'y',NaN,'speed',NaN);
end
notify(S,'InfoChanged');
gaitFig.Position = [150 160 900 450];
S.setTime(2); S.setZoom([1 3]);
shared.write_session(file,{'gait'});   % DLC stays out of the session
% change everything, then restore
hd.resolution.Value = 10; hd.pawList.Value = 1;
S.frameRate = 50; S.setTime(4);
shared.restore_session(shared.read_session(file));
verifyFalse(testCase,isgraphics(gaitFig) || isgraphics(dlcFig));   % all windows replaced
verifyEqual(testCase,fieldnames(S.fig),{'gait'});
verifyEqual(testCase,S.fig.gait.Position,[150 160 900 450]);
verifyEqual(testCase,S.gait.hd.resolution.Value,42);
verifyEqual(testCase,S.gait.hd.pawList.Value,2);
verifyEqual(testCase,numel(S.gait.paw),2);
verifyTrue(testCase,S.gait.stepsValid);
verifyEqual(testCase,[S.frameRate S.currentTime],[20 2]);
verifyEqual(testCase,S.currentZoom,[1 3]);
verifyFalse(testCase,S.closingAll);
end
function testEmgTypesFollowProcessingAndDeletion(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
cleanup = onCleanup(@()shared.exit_all(false));
fig = EMG.emg_viewer();
hd = S.emg.hd;
verifyEmpty(testCase,hd.datatype.Items);   % placeholder "no data"
verifyEqual(testCase,hd.datatype.Placeholder,'no data');
t = (0:1999)'/2000;   % 2 kHz: the default 500 Hz high pass is below Nyquist
S.emg.raw = struct('data',[sin(2*pi*50*t) cos(2*pi*50*t)],'t',t,'sample_rate',2000);
S.emg.processed = struct('data',{},'t',{},'sample_rate',{},'parameters',{});
S.emg.analog_channels = {'A','B'}; S.emg.display_name = pwd;
S.emg.trigger = struct('time',(0:0.1:0.9)','freq',10,'number',10);
notify(S,'InfoChanged'); notify(S,'EMGChanged');
verifyEqual(testCase,hd.datatype.Items,{'Raw'});
verifyTrue(testCase,logical(hd.deleteType.Enable));
% pre-process Raw: the delete button is off while the window is open
preprocess = findall(fig,'Type','uibutton','Text','Pre-Process');
callback = preprocess.ButtonPushedFcn; callback(preprocess,[]);
prep = S.emg.hd.prepGUI;
verifyFalse(testCase,logical(hd.deleteType.Enable));
rate = findall(prep,'Type','uinumericeditfield','Value',200); rate.Value = 300;
apply = findall(prep,'Type','uibutton','Text','Apply & Close');
callback = apply.ButtonPushedFcn; callback(apply,[]);
verifyFalse(testCase,isgraphics(prep));
verifyTrue(testCase,logical(hd.deleteType.Enable));
verifyEqual(testCase,hd.datatype.Items,{'Raw','Processed 1'});
verifyEqual(testCase,hd.datatype.Value,'Processed 1');
p = S.emg.processed(1);
verifyEqual(testCase,p.sample_rate,2000/7,'AbsTol',1e-9);   % achieved 2000/round(2000/300), not requested
verifyEqual(testCase,p.parameters.Source,'Raw');
verifyEqual(testCase,p.parameters.DownSampleRate,300);
% processing a processed type records it as the source
callback = preprocess.ButtonPushedFcn; callback(preprocess,[]);
prep = S.emg.hd.prepGUI;
check = findall(prep,'Type','uicheckbox','Text','Down Sample'); check.Value = false;
check = findall(prep,'Type','uicheckbox','Text','High Pass'); check.Value = false;   % 500 Hz is above Nyquist here
apply = findall(prep,'Type','uibutton','Text','Apply & Close');
callback = apply.ButtonPushedFcn; callback(apply,[]);
verifyEqual(testCase,S.emg.processed(2).parameters.Source,'Processed 1');
verifyEqual(testCase,S.emg.processed(2).sample_rate,2000/7,'AbsTol',1e-9);   % no down sampling
% delete Raw, then everything: metadata stays, the placeholder returns
S.emg = EMG.emg_delete(S.emg,'Raw'); notify(S,'EMGChanged');
verifyEqual(testCase,hd.datatype.Items,{'Processed 1','Processed 2'});
verifyTrue(testCase,S.has('emg'));
S.emg = EMG.emg_delete(S.emg,'Processed 1');
S.emg = EMG.emg_delete(S.emg,'Processed 1'); notify(S,'EMGChanged');
verifyFalse(testCase,S.has('emg'));
verifyEmpty(testCase,hd.datatype.Items);
verifyFalse(testCase,logical(hd.deleteType.Enable));
verifyEqual(testCase,S.emg.trigger.freq,10);
verifyEqual(testCase,S.getFrameRate(),10);   % frame timing still follows the trigger
end