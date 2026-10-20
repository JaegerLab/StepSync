function result = sta(emg, emg_t, event_time, varargin)
% GAIT.sta  Step-Triggered Average
%
%   result = GAIT.sta(emg, emg_t, event_time, Name, Value, ...)
%
%   Required inputs:
%     emg        : EMG signal vector
%     emg_t      : Time axis of EMG (seconds)
%     event_time : Array of event times (seconds)
%
%   Name-Value parameters:
%     'max_lag'   - Window half-width in seconds          (default: 0.5)
%     'method'    - Control method: 'dither' | 'random_time' |
%                   'isi_shuffle' | 'global' | 'none'     (default: 'dither')
%     'nRep'      - Repetitions for repeated methods      (default: 100)
%     'offset'    - Dither within [-offset, offset) sec   (default: 1)
%     'zscore'    - Store zscore flag (plot-time only)    (default: false)
%     'nStd'      - CI width in std devs                  (default: 3)
%     'plot'      - false / true / axes / figure handle   (default: false)
%
%   Output: flat struct with fields:
%     t, y, max_lag, method, nRep, offset, zscore, nStd,
%     random_t, random_mean, random_std, eventNum, sample_rate

    %% ── Parse name-value arguments ───────────────────────────────────────
    p = inputParser();
    p.addRequired('emg');
    p.addRequired('emg_t');
    p.addRequired('event_time');
    p.addParameter('max_lag',   0.5,      @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('method',    'dither', @(x) ischar(x) || isstring(x));
    p.addParameter('nRep',      100,      @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('offset',    1,        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('zscore',    false,    @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('nStd',      3,        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('plot',      false);
    p.parse(emg, emg_t, event_time, varargin{:});

    max_lag   = p.Results.max_lag;
    
    method    = char(p.Results.method);
    doControl = ~strcmp(method, 'none');
    nRep      = round(p.Results.nRep);
    offset    = p.Results.offset;
    zscore = logical(p.Results.zscore);
    nStd      = p.Results.nStd;
    plotArg   = p.Results.plot;

    % Validate method string
    valid_methods = {'none','global','random_time','isi_shuffle','dither'};
    if ~ismember(method, valid_methods)
        error('GAIT:sta:badMethod', ...
            'method must be one of: none, global, dither, random_time, isi_shuffle. Got: %s', method);
    end

    %% ── Pre-process signals ──────────────────────────────────────────────
    validateattributes(emg, {'numeric'}, {'vector','real','nonempty'});
    if ~any(isfinite(emg)), error('GAIT:sta:signal', 'EMG has no finite samples.'); end
    emg       = emg(:);
    emg(~isfinite(emg)) = NaN;
    emg_t     = emg_t(:);
    event_time = event_time(:);

    validateattributes(emg_t, {'numeric'}, {'vector','real','finite','increasing'});
    if numel(emg_t) ~= numel(emg) || numel(emg_t) < 2
        error('GAIT:sta:timebase', 'EMG and time must have the same length (at least 2).');
    end
    dt = median(diff(emg_t));
    if any(abs(diff(emg_t)-dt) > max(1e-9, dt*1e-3))
        error('GAIT:sta:timebase', 'STA requires regularly sampled EMG without timestamp gaps.');
    end
    sample_rate = 1/dt;
    traceLength = numel(emg);
    max_lag = min(max_lag, emg_t(end)-emg_t(1));
    event_time = sort(event_time(isfinite(event_time)));
    keep = event_time >= emg_t(1) & event_time <= emg_t(end);
    if any(~keep)
        warning('GAIT:sta:outOfBound', 'Some event times were out of bounds and removed.');
    end
    event_time = event_time(keep);
    event_index = round((event_time-emg_t(1))*sample_rate)+1;
    eventNum = numel(event_index);
    if eventNum == 0
        error('GAIT:sta:noEvents', 'No event times fall within the EMG recording.');
    end
    nRep = max(1, nRep);
    lag_samps = round(max_lag*sample_rate);
    t = (-lag_samps:lag_samps)'/sample_rate;
    tic
    [y_raw, sampleCount] = event_average(emg, event_index, lag_samps);
    elapsed_t = toc;

    %% ── Long-computation warning ─────────────────────────────────────────
    % Only relevant for repeated-method controls
    needs_rep = doControl && ~strcmp(method, 'global');
    actual_method = method;   % may be overridden to 'global' if user cancels

    if needs_rep
        estimated_total = elapsed_t * nRep;
        if estimated_total > 5
            msg = sprintf( ...
                ['Estimated computation time: %.1f seconds\n' ...
                 '(%d repetitions × %.2f s each)\n\n' ...
                 'Continue with ''%s''?\n' ...
                 'Or use the fast ''global'' control instead?'], ...
                estimated_total, nRep, elapsed_t, method);
            choice = questdlg(msg, 'Long Computation Warning', ...
                'Continue', 'Use Global', 'No Control', 'Continue');
            switch choice
                case 'No Control'
                    % Return minimal result with no control
                    actual_method = 'none';  
                    doControl = false;
                case 'Use Global'
                    actual_method = 'global';
                    % needs_rep     = false;
                    % fall through to control computation below
                % 'Continue' → proceed as requested
            end
        end
    end

    %% ── Random control ───────────────────────────────────────────────────
    random_mean = zeros(size(t));
    random_std  = zeros(size(t));

    if doControl
        switch actual_method
            %% ── global: whole-trace mean/std, no lag structure ───────────
            case 'global'
                random_mean = mean(emg, 'omitnan')*ones(size(t));
                random_std = std(emg, 'omitnan')./sqrt(sampleCount);
                random_std(sampleCount==0) = NaN;

            %% ── dither: jitter each real event by ±offset seconds ────────
            case 'dither'
                random_sta = zeros(2 * lag_samps + 1, nRep);
                for k = 1:nRep
                    rand_shift = round(offset * 2 * sample_rate .* (rand(size(event_index)) - 0.5));
                    rand_idx   = event_index + rand_shift;
                    rand_idx(rand_idx > traceLength | rand_idx <= 0) = [];
                    random_sta(:, k) = event_average(emg, rand_idx, lag_samps);
                end
                random_mean = mean(random_sta, 2, 'omitnan');
                random_std  = std(random_sta, 0, 2, 'omitnan');

            %% ── random_time: draw eventNum times uniformly ───────────────
            case 'random_time'
                random_sta = zeros(2 * lag_samps + 1, nRep);
                for k = 1:nRep
                    if eventNum <= traceLength
                        rand_idx = randperm(traceLength, eventNum);
                    else
                        rand_idx = randi(traceLength, eventNum, 1);
                    end
                    random_sta(:, k) = event_average(emg, rand_idx, lag_samps);
                end
                random_mean = mean(random_sta, 2, 'omitnan');
                random_std  = std(random_sta, 0, 2, 'omitnan');

            %% ── isi_shuffle: permute inter-step intervals ────────────────
            case 'isi_shuffle'
                isi = diff([emg_t(1); event_time]);
                random_sta = zeros(2 * lag_samps + 1, nRep);
                for k = 1:nRep
                    shuffled_isi  = isi(randperm(length(isi)));
                    rand_times = emg_t(1) + cumsum(shuffled_isi);
                    rand_idx = round((rand_times-emg_t(1))*sample_rate)+1;
                    rand_idx(rand_idx > traceLength | rand_idx <= 0) = [];
                    random_sta(:, k) = event_average(emg, rand_idx, lag_samps);
                end
                random_mean = mean(random_sta, 2, 'omitnan');
                random_std  = std(random_sta, 0, 2, 'omitnan');
        end
    end

    %% ── Build output struct ──────────────────────────────────────────────
    result = struct();
    result.t           = t;
    result.y           = y_raw;
    result.max_lag     = max_lag;
    result.method      = actual_method;   % what was actually computed
    result.nRep        = nRep;
    result.offset      = offset;
    result.zscore      = zscore;
    result.nStd        = nStd;
    result.random_t    = t;
    result.random_mean = random_mean;
    result.random_std  = random_std;
    result.eventNum    = eventNum;
    result.sample_rate = sample_rate;
    result.sampleCount = sampleCount;

    %% ── Optional plot ────────────────────────────────────────────────────
    if ~isequal(plotArg, false) && ~isequal(plotArg, 0)
        GAIT.plot_sta(result, plotArg);
    end
end

function [y, counts] = event_average(emg, indices, maxlag)
% Accumulate duplicate events; each lag uses only observed finite samples.
N = numel(emg);
if isempty(indices), y = nan(2*maxlag+1,1); counts = zeros(size(y)); return; end
train = accumarray(indices(:), 1, [N 1]);
valid = isfinite(emg);
emg(~valid) = 0;
numerator = xcorr(emg, train, maxlag);
counts = round(xcorr(double(valid), train, maxlag));
y = nan(size(numerator));
keep = counts > 0;
y(keep) = numerator(keep)./counts(keep);
end
