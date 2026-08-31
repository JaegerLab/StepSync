% function gait = gait_analysis_headfix(inputdata, frame_rate, resolution, paw_thres)

% gait = gait_analysis_headfix(inputdata, frame_rate, resolution, paw_thres)
%
% parameters:
%  inputdata: can be full filename to DLC, or a table of DLC readout.
%  frame_rate: frame/s in Hz
%  resolution: pixel/cm in the video.
%  paw_thres:  unit is cm

% inputdata = 'Z:\Analyzed_Data\Tiffany\analyzed videos\LS355\20251003\Basler_acA1920-150um__40003372__20251003_132404481DLC_resnet50_WheelRunningBelowMar24shuffle1_600000.csv';
if ischar(inputdata)
    % is a filename
    data = DLC.read_dlc(inputdata);
    gait.filename = inputdata;
elseif istable(inputdata)
    % is a table readout
    data = inputdata;
    gait.filename = inputdata.Properties.Description;
elseif isstruct(inputdata)

else 
    error('input error');
end

gait.frame_rate = frame_rate; % unit: frame/s
gait.resolution = resolution; % unit: pixel/cm

% convert speed from pixel/frame to cm/s: speed * speed_convert_factor
% speed*frame_rate/resolution = (pixel/frame)*(frame/s)*(cm/pixel) = cm/s
gait.speed_convert_factor = frame_rate/resolution; 

% use pixel/frame internally, use cm/s for output
gait.bodythres = body_thres;  % threshold should be irrelevant of frame rate
gait.pawthres = paw_thres;
% convert cm/s to pixel/frame, threshold's lower when frame rate's higher
bodythres = gait.bodythres/gait.speed_convert_factor;
pawthres = gait.pawthres/gait.speed_convert_factor;

MinTimeInterval = 5;
MaxTimeInterval = 30;
MaxStepLength = 250;
MaxSpeedLimit = 5;
MinSpeedThresh = 0.1;

gait.frameNum = height(data);
gait.t = (0:gait.frameNum-1)'./gait.frame_rate; % convert frame to second

spaceFiller = zeros(gait.frameNum,1);
pawNames = {'L_forepaw','R_forepaw','L_hindpaw','R_hindpaw'};
gait.pawNames = pawNames;
template = struct('name', '', ...
                  'x', spaceFiller, ...
                  'y', spaceFiller, ...
                  'speed', spaceFiller, ...
                  'pawUp', spaceFiller, ...
                  'pawDown', spaceFiller, ...
                  'peak', spaceFiller, ...
                  'maxspeed', spaceFiller, ...
                  'valley', spaceFiller, ...
                  'interval', spaceFiller, ...
                  'stride', spaceFiller, ...
                  'swing', spaceFiller, ...
                  'stance', spaceFiller, ...
                  'swingPercent', spaceFiller ...
                 );
gait.paw = repmat(template, 4, 1);

data.