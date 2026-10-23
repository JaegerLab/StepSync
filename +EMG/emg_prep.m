function [new_data, new_t, new_fs] = emg_prep(data, t, options, fs)
% pre-process EMG data, high-pass, rectify, smooth then downsample
% Syntax
%  [new_data, new_t, new_fs] = EMG.emg_prep(data, t, options, fs)
%
% Parameters:
%  data: 2-D array, each channel is vertical vector
%  t: 1-D array, time axis.
%  options: a structure with the following optional field
%       HighPassFreq: a number. frequency to high pass filter
%       FiltFilt: boolean. true uses filtfilt, false (default) uses filter
%       Rectify: boolean. true or false(default)
%       DownSampleRate: a number. frequency to down sample to
%  fs: sample rate of data (default: from t)
% Outputs:
%  new_data: processed data. data at negative time are truncated.
%  new_t: down sampled t. negative time are truncated.
%  new_fs: achieved sample rate, fs/round(fs/DownSampleRate), or fs
%
% Li Su. 2/27/2026

%%
if nargin < 4 || isempty(fs), fs = 1/mean(diff(t)); end
new_fs = fs;
new_data = data;

hd = waitbar(0,'Processing ...', 'Name', 'Processing');
closeBar = onCleanup(@()delete(hd));   % also on errors
drawnow

if isfield(options, 'HighPassFreq')
    waitbar(1/6, hd, 'Filtering ...')
    f = designfilt('highpassiir', 'FilterOrder', 4, ...
                   'HalfPowerFrequency', options.HighPassFreq, 'SampleRate', fs);
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
    downsample_factor = max(1, round(fs / options.DownSampleRate));
    smoothWidth = round(2.5 * downsample_factor);
    new_data = shared.fastsmooth(new_data, smoothWidth,1,1);

    % truncate and downsample
    waitbar(2/3, hd, 'Downsampling')
    new_data = downsample(new_data(t>=0,:), downsample_factor);
    new_t = downsample(t(t>=0), downsample_factor);
    new_fs = fs / downsample_factor;
else
    % truncate (discard negative time)
    new_data = new_data(t>=0,:);
    new_t = t(t>=0);
end

clear closeBar

