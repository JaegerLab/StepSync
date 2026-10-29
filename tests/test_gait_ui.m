function tests = test_gait_ui
% Desktop integration tests: require MATLAB graphics and Signal Processing Toolbox.
tests = functiontests(localfunctions);
end

function testSwitchingPawsAndTracesRecalculates(testCase)
assumeTrue(testCase, usejava('desktop'), 'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close StepSync before running UI tests.');
S.frameRate = 20;
gait.gait_viewer();
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
    S.gait.paw(k).rawX = x+(k-1)*10;
    S.gait.paw(k).rawY = circshift(x,1)+(k-1)*20;
    S.gait.paw(k).thresh = struct('x',NaN,'y',NaN,'speed',NaN);
end
notify(S,'InfoChanged');   % gait recalculates on a time-base change
verifyTrue(testCase,S.gait.stepsValid);
first = S.gait.paw(1).rising;
% Other viewers read steps through gait.current_steps, never gait's controls.
steps = gait.current_steps(S);
verifyEqual(testCase,steps.idx,first(:));
verifyEqual(testCase,steps.t,S.gait.t(first(:)));
verifyEqual(testCase,steps.x,S.gait.paw(1).rawX(first(:)));
hd.stepCheck.Value = false;
callback = hd.stepCheck.ValueChangedFcn; callback(hd.stepCheck,[]);
verifyEmpty(testCase,gait.current_steps(S));
hd.stepCheck.Value = true;
callback(hd.stepCheck,[]);
verifyNotEmpty(testCase,gait.current_steps(S));
% Mask GUI must work with the new data model (no per-paw .trace).
verifyFalse(testCase,isfield(S.gait.paw,'trace'));
maskFig = gait.mask_GUI([100 100]);
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
verifyError(testCase,@()callback(hd.pawList,[]),'gait:maskSize');
verifyFalse(testCase,gait.steps_current(S));
verifyEmpty(testCase,gait.current_steps(S));
end

function testEphysInfoPreservesMappedChannelIdentity(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
ephys.ephys_viewer();
cleanup = onCleanup(@()shared.exit_all(false));
hd = S.ephys.hd;
S.ephys.raw = struct('data',zeros(101,2),'t',(0:0.01:1)','sampleRate',100);
S.ephys.analogChannels = {'raw1','raw2'};
S.ephys.displayName = pwd;
S.ephys.chMapping = table({'B';'A'},{'mapped1';'mapped2'},'VariableNames',{'Muscle','Names'});
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
figures = {ephys.ephys_viewer(), pose.pose_viewer(), gait.gait_viewer()};
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
poseFig = shared.open_module('Pose');
verifyFalse(testCase,isgraphics(launcher));   % opening a module closes the launcher
gaitFig = shared.open_module('gait');
verifyEqual(testCase,shared.open_module('pose'),poseFig);   % no second window
windowMenu = findall(gaitFig,'Type','uimenu','Tag','Window');
items = flip(windowMenu.Children);
verifyEqual(testCase,{items.Text},{'Ephys','Video','Pose','Gait','Open All','Bring All to Top'});
verifyEqual(testCase,logical([items(1:4).Checked]),[false false true true]);
verifyEqual(testCase,{items([1:5 end]).Accelerator},{'E','I','P','G','A','T'});
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
verifyEqual(testCase,sort(fieldnames(S.fig))',{'ephys','gait','pose','video'});
verifyEqual(testCase,S.fig.pose,poseFig);
% Exit all closes everything and resets the session
S.frameRate = 30;
shared.exit_all(false);
verifyFalse(testCase,isvalid(S));
verifyFalse(testCase,isgraphics(poseFig) || isgraphics(gaitFig));
verifyEmpty(testCase,findall(groot,'Type','figure','Name','StepSync Video'));
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
gaitFig = gait.gait_viewer();
poseFig = pose.pose_viewer();
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
    S.gait.paw(k).rawX = x+(k-1)*10;
    S.gait.paw(k).rawY = circshift(x,1)+(k-1)*20;
    S.gait.paw(k).thresh = struct('x',NaN,'y',NaN,'speed',NaN);
end
notify(S,'InfoChanged');
gaitFig.Position = [150 160 900 450];
S.setTime(2); S.setZoom([1 3]);
shared.write_session(file,{'gait'});   % pose stays out of the session
% change everything, then restore
hd.resolution.Value = 10; hd.pawList.Value = 1;
S.frameRate = 50; S.setTime(4);
shared.restore_session(shared.read_session(file));
verifyFalse(testCase,isgraphics(gaitFig) || isgraphics(poseFig));   % all windows replaced
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
function testEphysTriggerMenuAndFrameRateField(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
cleanup = onCleanup(@()shared.exit_all(false));
ephys.ephys_viewer(); pose.pose_viewer();
menu = S.ephys.hd.trigger; rate = S.pose.hd.frameRate;
verifyEqual(testCase,menu.Items,{'No data'});
verifyEqual(testCase,[rate.Value string(rate.FontAngle)],["1" "italic"]);   % automatic: frame units
verifyEmpty(testCase,findall(S.fig.ephys,'Type','uibutton','Text','Push Frame Rate'));
verifyEmpty(testCase,findall(S.fig.pose,'Type','uibutton','Text','GetFrameRate'));
% a recording with a 100 Hz camera line and a single long pulse
t = (0:999)'/1000;
S.ephys.raw = struct('data',zeros(1000,1),'t',t,'sampleRate',1000);
S.ephys.processed = struct('data',{},'t',{},'sampleRate',{},'parameters',{});
S.ephys.analogChannels = {'A'}; S.ephys.displayName = pwd;
S.ephys.digital = ephys.ttl_channels(t,[mod(0:999,10)'<2, t>=0.1 & t<0.9]);
notify(S,'InfoChanged');
verifyEqual(testCase,menu.Items,{'Select trigger channel', ...
    'DIN-00: 99 TTL, 2 ms, 100 Hz','DIN-01: 1 TTL, 800 ms, - Hz'});
verifyEqual(testCase,menu.Value,0);
% a single pulse cannot be a trigger: refused, the previous choice is kept
callback = menu.ValueChangedFcn;
menu.Value = 2; callback(menu,struct('PreviousValue',0));
verifyEqual(testCase,menu.Value,0);
verifyFalse(testCase,isfield(S.ephys,'trigger'));
% a typed-in rate is cleared by choosing a trigger channel
S.setFrameRate(30);
verifyEqual(testCase,[rate.Value string(rate.FontAngle)],["30" "normal"]);
menu.Value = 1; callback(menu,struct('PreviousValue',0));
verifyEqual(testCase,[S.ephys.trigger.number S.ephys.trigger.freq S.frameRate],[99 100 0],'AbsTol',1e-9);
verifyEqual(testCase,S.ephys.trigger.channel,'DIN-00');
verifyEqual(testCase,[rate.Value string(rate.FontAngle)],["100" "italic"]);
% clearing the field returns to automatic
rate.Value = []; rateCallback = rate.ValueChangedFcn; rateCallback(rate,[]);
verifyEqual(testCase,S.frameRate,0);
verifyEqual(testCase,rate.Value,100,'AbsTol',1e-9);
% 'Select trigger channel' removes the trigger
menu.Value = 0; callback(menu,struct('PreviousValue',1));
verifyFalse(testCase,isfield(S.ephys,'trigger'));
verifyEqual(testCase,rate.Value,1);
% no digital channel
S.ephys.digital = S.ephys.digital([]); notify(S,'InfoChanged');
verifyEqual(testCase,menu.Items,{'No digital channel'});
end
function testEphysTypesFollowProcessingAndDeletion(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
cleanup = onCleanup(@()shared.exit_all(false));
fig = ephys.ephys_viewer();
hd = S.ephys.hd;
verifyEmpty(testCase,hd.datatype.Items);   % placeholder "no data"
verifyEqual(testCase,hd.datatype.Placeholder,'no data');
t = (0:1999)'/2000;   % 2 kHz: the default 500 Hz high pass is below Nyquist
S.ephys.raw = struct('data',[sin(2*pi*50*t) cos(2*pi*50*t)],'t',t,'sampleRate',2000);
S.ephys.processed = struct('data',{},'t',{},'sampleRate',{},'parameters',{});
S.ephys.analogChannels = {'A','B'}; S.ephys.displayName = pwd;
S.ephys.trigger = struct('time',(0:0.1:0.9)','freq',10,'number',10);
notify(S,'InfoChanged'); notify(S,'EphysChanged');
verifyEqual(testCase,hd.datatype.Items,{'Raw'});
verifyTrue(testCase,logical(hd.deleteType.Enable));
% pre-process Raw: the delete button is off while the window is open
preprocess = findall(fig,'Type','uibutton','Text','Pre-Process');
callback = preprocess.ButtonPushedFcn; callback(preprocess,[]);
prep = S.ephys.hd.prepGUI;
verifyFalse(testCase,logical(hd.deleteType.Enable));
rate = findall(prep,'Type','uinumericeditfield','Value',200); rate.Value = 300;
apply = findall(prep,'Type','uibutton','Text','Apply & Close');
callback = apply.ButtonPushedFcn; callback(apply,[]);
verifyFalse(testCase,isgraphics(prep));
verifyTrue(testCase,logical(hd.deleteType.Enable));
verifyEqual(testCase,hd.datatype.Items,{'Raw','Processed 1'});
verifyEqual(testCase,hd.datatype.Value,'Processed 1');
p = S.ephys.processed(1);
verifyEqual(testCase,p.sampleRate,300);   % exactly the requested rate
verifyEqual(testCase,p.parameters.Source,'Raw');
verifyEqual(testCase,p.parameters.DownSampleRate,300);
% processing a processed type records it as the source
callback = preprocess.ButtonPushedFcn; callback(preprocess,[]);
prep = S.ephys.hd.prepGUI;
% the window shows the settings Processed 1 was made with; Raw shows defaults
rate = findall(prep,'Type','uinumericeditfield','Value',300);
verifyNumElements(testCase,rate,1);
hd.datatype.Value = 'Raw'; callback = hd.datatype.ValueChangedFcn; callback(hd.datatype,[]);
verifyEqual(testCase,rate.Value,200);
hd.datatype.Value = 'Processed 1'; callback(hd.datatype,[]);
verifyEqual(testCase,rate.Value,300);
check = findall(prep,'Type','uicheckbox','Text','Down Sample'); check.Value = false;
check = findall(prep,'Type','uicheckbox','Text','Filter'); check.Value = false;   % 500 Hz is above Nyquist here
apply = findall(prep,'Type','uibutton','Text','Apply & Close');
callback = apply.ButtonPushedFcn; callback(apply,[]);
verifyEqual(testCase,S.ephys.processed(2).parameters.Source,'Processed 1');
verifyEqual(testCase,S.ephys.processed(2).sampleRate,300);   % no down sampling: the source's rate
verifyEqual(testCase,S.ephys.processed(2).t,S.ephys.processed(1).t);
% delete Raw, then everything: metadata stays, the placeholder returns
S.ephys = ephys.ephys_delete(S.ephys,'Raw'); notify(S,'EphysChanged');
verifyEqual(testCase,hd.datatype.Items,{'Processed 1','Processed 2'});
verifyTrue(testCase,S.has('ephys'));
S.ephys = ephys.ephys_delete(S.ephys,'Processed 1');
S.ephys = ephys.ephys_delete(S.ephys,'Processed 1'); notify(S,'EphysChanged');
verifyFalse(testCase,S.has('ephys'));
verifyEmpty(testCase,hd.datatype.Items);
verifyFalse(testCase,logical(hd.deleteType.Enable));
verifyEqual(testCase,S.ephys.trigger.freq,10);
verifyEqual(testCase,S.getFrameRate(),10);   % frame timing still follows the trigger
end
function testPoseTimelineStaysBelowTraces(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close StepSync before running UI tests.');
cleanup = onCleanup(@()shared.exit_all(false));
pose.pose_viewer();
hd = S.pose.hd;
n = 50;
S.pose.table = table((1:n)',(1:n)',ones(n,1),'VariableNames',{'paw_x','paw_y','paw_likelihood'});
S.pose.table.Properties.UserData = {'paw'};
S.pose.seg = []; S.pose.segBodypart = '';
hd.bodypart.Items = {'paw'}; hd.bodypart.Enable = 'on';
% session load order: traces (PoseChanged) before the time (TimeChanged)
notify(S,'InfoChanged');
S.notifyPose('load');
notify(S,'TimeChanged');
hd = S.pose.hd;
yyaxis(hd.ax,'left');
children = allchild(hd.ax);   % first child is drawn on top; the time line is hidden from Children
verifyGreaterThan(testCase,find(children==hd.timelinePose),find(children==hd.xplot));
verifyGreaterThan(testCase,find(children==hd.timelinePose),find(children==hd.yplot));
end