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
%     'offset'    - Dither max offset in seconds          (default: 2)
%     'normalize' - Store normalize flag (plot-time only) (default: false)
%     'nStd'      - CI width in std devs                  (default: 3)
%     'plot'      - false / true / axes / figure handle   (default: false)
%
%   Output: flat struct with fields:
%     t, y, max_lag, method, nRep, offset, normalize, nStd,
%     random_t, random_mean, random_std, eventNum, sample_rate

    %% ── Parse name-value arguments ───────────────────────────────────────
    p = inputParser();
    p.addRequired('emg');
    p.addRequired('emg_t');
    p.addRequired('event_time');
    p.addParameter('max_lag',   0.5,      @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('method',    'dither', @(x) ischar(x) || isstring(x));
    p.addParameter('nRep',      100,      @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('offset',    1,        @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('normalize', false,    @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('nStd',      3,        @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('plot',      false);
    p.parse(emg, emg_t, event_time, varargin{:});

    max_lag   = p.Results.max_lag;
    
    method    = char(p.Results.method);
    doControl = ~strcmp(method, 'none');
    nRep      = round(p.Results.nRep);
    offset    = p.Results.offset;
    normalize = logical(p.Results.normalize);
    nStd      = p.Results.nStd;
    plotArg   = p.Results.plot;

    % Validate method string
    valid_methods = {'none','global','random_time','isi_shuffle','dither'};
    if ~ismember(method, valid_methods)
        error('GAIT:sta:badMethod', ...
            'method must be one of: none, global, dither, random_time, isi_shuffle. Got: %s', method);
    end

    %% ── Pre-process signals ──────────────────────────────────────────────
    emg       = emg(:);
    emg_t     = emg_t(:);
    event_time = event_time(:);

    sample_rate = round(1 / mean(diff(emg_t)));
    max_lag = min(max_lag, max(emg_t));  % clamp to trace length

    % Discard negative-time samples
    emg(emg_t <= 0) = [];
    emg_t(emg_t <= 0) = [];
    traceLength = length(emg);

    % Clean event times
    event_time(isnan(event_time)) = [];
    event_index = round(event_time .* sample_rate);

    out_of_bound = event_index > traceLength | event_index <= 0;
    if any(out_of_bound)
        event_index(out_of_bound) = [];
        warning('GAIT:sta:outOfBound', 'Some event times were out of bounds and removed.');
    end

    eventNum   = length(event_index);
    lag_samps  = round(max_lag * sample_rate);

    % Build event train
    event_train = zeros(traceLength, 1);
    event_train(event_index) = 1 / eventNum;

    %% ── Compute STA ─────────────────────────────────────────────────────
    tic
    [y_raw, m_lags] = xcorr(emg, event_train, lag_samps);
    t = m_lags(:) ./ sample_rate;
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
                random_mean = mean(emg) ;
                random_std  = std(emg) ;

            %% ── dither: jitter each real event by ±offset seconds ────────
            case 'dither'
                random_sta = zeros(2 * lag_samps + 1, nRep);
                for k = 1:nRep
                    rand_shift = round(offset * 2 * sample_rate .* (rand(size(event_index)) - 0.5));
                    rand_idx   = event_index + rand_shift;
                    rand_idx(rand_idx > traceLength | rand_idx <= 0) = [];
                    rand_train = zeros(traceLength, 1);
                    rand_train(rand_idx) = 1 / numel(rand_idx);
                    random_sta(:, k) = xcorr(emg, rand_train, lag_samps);
                end
                random_mean = mean(random_sta, 2);
                random_std  = std(random_sta, 0, 2);

            %% ── random_time: draw eventNum times uniformly ───────────────
            case 'random_time'
                random_sta = zeros(2 * lag_samps + 1, nRep);
                for k = 1:nRep
                    rand_idx   = randperm(traceLength, eventNum);
                    rand_train = zeros(traceLength, 1);
                    rand_train(rand_idx) = 1 / eventNum;
                    random_sta(:, k) = xcorr(emg, rand_train, lag_samps);
                end
                random_mean = mean(random_sta, 2);
                random_std  = std(random_sta, 0, 2);

            %% ── isi_shuffle: permute inter-step intervals ────────────────
            case 'isi_shuffle'
                isi = diff([0; event_time]);
                random_sta = zeros(2 * lag_samps + 1, nRep);
                for k = 1:nRep
                    shuffled_isi  = isi(randperm(length(isi)));
                    rand_times    = cumsum(shuffled_isi);
                    rand_idx      = round(rand_times .* sample_rate);
                    rand_idx(rand_idx > traceLength | rand_idx <= 0) = [];
                    rand_train = zeros(traceLength, 1);
                    rand_train(rand_idx) = 1 / eventNum;
                    random_sta(:, k) = xcorr(emg, rand_train, lag_samps);
                end
                random_mean = mean(random_sta, 2);
                random_std  = std(random_sta, 0, 2);
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
    result.normalize   = normalize;
    result.nStd        = nStd;
    result.random_t    = t;
    result.random_mean = random_mean;
    result.random_std  = random_std;
    result.eventNum    = eventNum;
    result.sample_rate = sample_rate;

    %% ── Optional plot ────────────────────────────────────────────────────
    if ~isequal(plotArg, false) && ~isequal(plotArg, 0)
        GAIT.plot_sta(result, plotArg);
    end
end
