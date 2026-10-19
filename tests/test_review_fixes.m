function tests = test_review_fixes
tests = functiontests(localfunctions);
end

function testFrameClockUsesMeasuredOriginAndTailConvention(testCase)
ttl = [2;2.01;2.021;2.03];
verifyEqual(testCase,shared.frame_times(4,100,ttl),ttl);
verifyEqual(testCase,shared.frame_times(3,100,ttl),ttl(1:3));
t = shared.frame_times(5,100,ttl);
verifyEqual(testCase,t(1:4),ttl);
verifyTrue(testCase,isnan(t(5)));
verifyEqual(testCase,shared.time_to_frame(t,[0 2.011 99]),[1 2 4]);
verifyError(testCase,@()shared.frame_times(7,100,ttl),'StepSync:timing:countMismatch');
verifyEqual(testCase,shared.frame_times(3,100,[]),[0.01;0.02;0.03]);
end

function testGlobalUsesEventCountNotRepetitions(testCase)
t = (0:0.01:3)';
x = sin(2*pi*3*t)+0.4*cos(2*pi*7*t);
events = (0.5:0.1:2.5)';
a = GAIT.sta(x,t,events,'method','global','max_lag',0.1,'nRep',1);
b = GAIT.sta(x,t,events,'method','global','max_lag',0.1,'nRep',1000);
verifyEqual(testCase,a.random_std,b.random_std,'AbsTol',1e-12);
verifyEqual(testCase,a.random_std,std(x)./sqrt(a.sampleCount),'AbsTol',1e-12);
verifyEqual(testCase,a.sampleCount,numel(events)*ones(size(a.t)));
end

function testNearZeroIsEstimatedFromRestRatherThanCrossingThreshold(testCase)
fs = 100;
t = (1:500)'/fs;
rest = 0.2+0.02*sin(2*pi*7*t);
movement = 12+sin(2*pi*3*t);
speed = [rest;movement;rest;movement;rest];
[threshold,info] = GAIT.auto_rest_threshold(speed,fs);
verifyTrue(testCase,isfinite(threshold));
verifyGreaterThan(testCase,threshold,0.19);
verifyLessThan(testCase,threshold,0.23);
verifyGreaterThan(testCase,nnz(info.restMask),100);
verifyLessThan(testCase,max(speed(info.restMask)),1);
end

function testNoRestEstimateDoesNotInventOnsets(testCase)
[threshold,~] = GAIT.auto_rest_threshold(5*ones(500,1),100);
verifyTrue(testCase,isnan(threshold));
s = GAIT.detect_steps([0;0;4;4;0],true(5,1),3,10,threshold);
verifyEqual(testCase,s.rising,2);
verifyEmpty(testCase,s.onset);
verifyEmpty(testCase,s.offset);
end

function testBinaryScalingUsesIndividualUnits(testCase)
channels = struct('bit_volts',{0.195,0.001},'units',{'uV','V'});
actual = EMG.scale_binary_channels([10 10;-10 -10],channels,'uV');
verifyEqual(testCase,actual,[1.95 10000;-1.95 -10000],'AbsTol',1e-10);
verifyEqual(testCase,EMG.scale_binary_channels(10,channels(2),'V'),0.01,'AbsTol',1e-12);
end

function testCsvRoundTripIgnoresPreviewAndFillsMissingLikelihood(testCase)
filename = [tempname '.csv'];
cleanup = onCleanup(@()delete(filename)); %#ok<NASGU>
t = table([1;2],[3;4],[0.8;0.9],[5;6],[7;8],[99;99],[88;88], ...
    'VariableNames',{'paw_x','paw_y','paw_likelihood','tail_x','tail_y','temp_x','temp_y'});
t.Properties.UserData = {'paw','tail','temp'};
t.Properties.Description = 'C:\source\pose.csv';
t = addprop(t,'Scorer','table'); t.Properties.CustomProperties.Scorer = 'test_model';
DLC.save_csv(filename,t);
loaded = DLC.read_csv(filename);
verifyEqual(testCase,height(loaded),2);
verifyEqual(testCase,width(loaded),6);
verifyEqual(testCase,loaded.paw_x,t.paw_x);
verifyEqual(testCase,loaded.tail_y,t.tail_y);
verifyTrue(testCase,all(isnan(loaded.tail_likelihood)));
verifyEqual(testCase,loaded.Properties.CustomProperties.Scorer,'test_model');
verifyFalse(testCase,any(startsWith(loaded.Properties.VariableNames,'temp_')));
end

function testLikelihoodConversionIsGradedAndRepeatable(testCase)
seg = struct('flag',[2;2;1;-1;-2;-3;0], 'len',[10;1;1;1;1;1;1], 'win_width',5);
p = DLC.seg_likelihood(seg);
verifyEqual(testCase,p,[0.95*ones(10,1);1;0.9;0.1;0.5;0;0.5],'AbsTol',1e-12);
verifyEqual(testCase,p,DLC.seg_likelihood(seg));
end

function testLegacySessionMigrationPreservesFramesAndRules(testCase)
saved = struct('frameRate',100,'currentTime',0.02,'currentZoom',[0 1]);
saved.emg.trigger.time = (2:0.01:3)';
rules = table(0.01,0.03,'VariableNames',{'FromTime','ToTime'});
saved.gait.maskParam = struct('Rules',rules,'Speed',[1;2;NaN], ...
    'SpeedTime',[0.01;0.02;0.03],'SpeedSource','DLC: paw');
saved.gait.speedFactor = 5;
actual = shared.migrate_session_time(saved);
verifyEqual(testCase,actual.currentTime,2.01,'AbsTol',1e-12);
verifyEqual(testCase,actual.gait.maskParam.Rules.FromTime,2,'AbsTol',1e-12);
verifyEqual(testCase,actual.gait.maskParam.Rules.ToTime,2.02,'AbsTol',1e-12);
verifyEqual(testCase,actual.gait.maskParam.Speed(1:2),[0.2;0.4],'AbsTol',1e-12);
verifyEqual(testCase,actual.gait.maskParam.SpeedUnits,'pixels/frame');
verifyEmpty(testCase,actual.gait.maskParam.SpeedTime);
verifyEqual(testCase,shared.migrate_session_time(actual),actual);
end
