function [new_data, new_t] = emg_prep(data, t, options, fs)
% pre-process EMG data, filter, rectify, smooth then downsample
% Syntax
%  [new_data, new_t] = EMG.emg_prep(data, t, options, fs)
%
% Parameters:
%  data: 2-D array, each channel is vertical vector
%  t: 1-D array, time axis.
%  options: a structure with the following optional field
%       FilterType: 'highpass', 'lowpass', 'bandpass' or 'bandstop'.
%           Default: from the frequencies given (both: 'bandpass')
%       HighPassFreq: a number. high pass cutoff (highpass, band edge)
%       LowPassFreq: a number. low pass cutoff (lowpass, band edge)
%           bandpass/bandstop use the band between the two frequencies
%       FiltFilt: boolean. true uses filtfilt, false (default) uses filter
%       Rectify: boolean. true or false(default)
%       DownSampleRate: a number. frequency to down sample to: smooth, then
%           interpolate at multiples of 1/DownSampleRate from time 0
%  fs: sample rate of data (default: from t)
% Outputs:
%  new_data: processed data. data at negative time are truncated.
%  new_t: down sampled t. negative time are truncated.
%
% Li Su. 2/27/2026

%%
if nargin < 4 || isempty(fs), fs = 1/mean(diff(t)); end
new_data = data;

hd = waitbar(0,'Processing ...', 'Name', 'Processing');
closeBar = onCleanup(@()delete(hd));   % also on errors
drawnow

f = makeFilter(options, fs);
if ~isempty(f)
    waitbar(1/6, hd, 'Filtering ...')
    if isfield(options, 'FiltFilt') && options.FiltFilt
        new_data = filtfilt(f, new_data);
    else
        new_data = filter(f, new_data);
    end
end

if isfield(options, 'Rectify') && options.Rectify
    new_data = abs(new_data);
end

if isfield(options, 'DownSampleRate')
    % smooth
    waitbar(1/3, hd, 'Smoothing')
    validateattributes(options.DownSampleRate, {'numeric'}, {'scalar','real','finite','positive','<=',fs});
    smoothWidth = max(1, round(2.5 * fs / options.DownSampleRate));
    new_data = shared.fastsmooth(new_data, smoothWidth,1,1);

    % interpolate on an exact grid k/DownSampleRate, from time 0
    waitbar(2/3, hd, 'Downsampling')
    k = max(0, ceil(t(1) * options.DownSampleRate - 1e-9)) : ...
        floor(t(end) * options.DownSampleRate + 1e-9);
    new_t = k(:) / options.DownSampleRate;
    new_data = interp1(t, new_data, new_t, 'linear');
else
    % truncate (discard negative time)
    new_data = new_data(t>=0,:);
    new_t = t(t>=0);
end

clear closeBar

end

function f = makeFilter(options, fs)
% 4th-order IIR (Butterworth) filter described by options, [] for none
f = [];
hasHigh = isfield(options, 'HighPassFreq');
hasLow = isfield(options, 'LowPassFreq');
if isfield(options, 'FilterType')
    type = lower(options.FilterType);
elseif hasHigh && hasLow
    type = 'bandpass';
elseif hasHigh
    type = 'highpass';
elseif hasLow
    type = 'lowpass';
else
    return
end

switch type
    case 'highpass'
        f = designfilt('highpassiir', 'FilterOrder', 4, ...
            'HalfPowerFrequency', options.HighPassFreq, 'SampleRate', fs);
    case 'lowpass'
        f = designfilt('lowpassiir', 'FilterOrder', 4, ...
            'HalfPowerFrequency', options.LowPassFreq, 'SampleRate', fs);
    case {'bandpass', 'bandstop'}
        band = sort([options.HighPassFreq options.LowPassFreq]);
        if band(1) == band(2)
            error('EMG:prep:band', 'The two band frequencies must differ.');
        end
        f = designfilt([type 'iir'], 'FilterOrder', 4, ...
            'HalfPowerFrequency1', band(1), 'HalfPowerFrequency2', band(2), ...
            'SampleRate', fs);
    otherwise
        error('EMG:prep:filterType', 'Unknown FilterType ''%s''.', options.FilterType);
end
end
