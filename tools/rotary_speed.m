function [speed, t] = rotary_speed(WheelData, fs)
% Convert event-based rotary encoder position to fixed-rate speed.
%
%   [speed, t] = rotary_speed(WheelData, fs)
%
% Inputs
%   WheelData.Positions : encoder positions, range (-512, 512]
%   WheelData.Times     : timestamps corresponding to Positions
%   fs                  : desired output sampling rate (Hz)
%
% Outputs
%   speed : angular velocity in degree / second
%   t     : uniformly sampled timestamps

    pos  = double(WheelData.Positions(:));
    time = double(WheelData.Times(:));

    if numel(pos) ~= numel(time)
        error('WheelData.Positions and WheelData.Times must have the same length.');
    end

    if numel(pos) < 2
        error('At least two encoder samples are required.');
    end

    % remove all the non moving data points (duplicates)
    nonMove = find(diff(time)==0 & diff(pos)==0)+1;
    pos(nonMove)=[];
    time(nonMove)=[];

    if any(diff(time) <= 0) 
        error('WheelData.Times must be strictly increasing.');
    end

    %% Unwrap circular encoder position
    encoderRange = 1024;
    halfRange = encoderRange / 2;

    dp = diff(pos);

    % Map differences to [-512, 512)
    dp = mod(dp + halfRange, encoderRange) - halfRange;

    posUnwrapped = [pos(1); pos(1) + cumsum(dp)];

    %% Uniform time vector
    dt = 1 / fs;
    t = (time(1):dt:time(end)).';    

    %% Interpolate position onto uniform sampling grid
    %
    % Linear interpolation is appropriate here because encoder events
    % indicate crossings of successive position counts.
    posUniform = interp1(time, posUnwrapped, t, 'linear');

    %% Differentiate
    %
    % gradient preserves the same number of samples as t.
    speed = gradient(posUniform, dt) * 360 / encoderRange;
end