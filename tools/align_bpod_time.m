function [tOut, info] = align_bpod_time(tBpod, ttlBpod, ttlEphys, varargin)
% Map Bpod state-machine times onto the ephys clock using shared camera TTLs.
%
%   [tOut, info] = align_bpod_time(tBpod, ttlBpod, ttlEphys)
%   [tOut, info] = align_bpod_time(..., 'Method', 'interp', 'MaxResidual', 1e-3)
%
% Bpod generates the camera trigger and the ephys system records it, so each
% pulse has a time on both clocks. These pulse pairs define the mapping.
%
% Inputs
%   tBpod    : times to convert, on the Bpod state-machine clock (s)
%   ttlBpod  : camera pulse times on the Bpod clock (s),
%              e.g. RawEvents.Trial{1}.Events.GlobalTimer2_Start
%   ttlEphys : the same pulses on the ephys clock (s), rising edges, with
%              time 0 at the start of the recording (the StepSync timeline)
%
% Options
%   'Method'      : 'linear' (default) fits offset + clock-rate difference;
%                   'interp' interpolates between pulses (absorbs non-linear
%                   drift; times outside the pulse range use the linear fit)
%   'MaxResidual' : largest acceptable residual of the linear fit (s),
%                   default 1e-3. Larger residuals give a warning.
%   'Offset'      : constant added after mapping (s), default 0. Use it for
%                   a device whose own clock is offset from the state machine.
%
% Outputs
%   tOut : tBpod on the ephys clock (s)
%   info : slope, offset, drift_ppm, residual_rms, residual_max (s),
%          n_pulses, residuals
%
% Example (wheel session, Bpod + Open Ephys)
%   load(bpodFile, 'SessionData');
%   ttlB = SessionData.RawEvents.Trial{1}.Events.GlobalTimer2_Start;
%   W = SessionData.WheelData;
%   W.Times = align_bpod_time(W.Times, ttlB, ttlEphys);
%   [speed, t] = rotary_speed(W, 100);
%   writematrix([t speed], 'rotary_speed.csv');

    p = inputParser;
    p.addParameter('Method', 'linear', @(s) any(strcmpi(s, {'linear', 'interp'})));
    p.addParameter('MaxResidual', 1e-3, @(v) isscalar(v) && v > 0);
    p.addParameter('Offset', 0, @(v) isscalar(v) && isfinite(v));
    p.parse(varargin{:});
    opt = p.Results;

    tBpod    = double(tBpod(:));
    ttlBpod  = double(ttlBpod(:));
    ttlEphys = double(ttlEphys(:));

    %% Pair pulses
    %
    % A regular pulse train cannot be matched by its intervals: shifting by
    % one pulse fits just as well. Pulses are therefore paired from the
    % first one, as StepSync pairs frames with TTLs.
    nB = numel(ttlBpod);
    nE = numel(ttlEphys);
    if min(nB, nE) < 2
        error('At least two camera pulses are required on each clock.');
    end
    if nB ~= nE
        warning(['Pulse counts differ (Bpod %d, ephys %d). Pairing from the ' ...
            'first pulse and using the first %d.'], nB, nE, min(nB, nE));
    end
    n = min(nB, nE);
    ttlBpod  = ttlBpod(1:n);
    ttlEphys = ttlEphys(1:n);

    if any(diff(ttlBpod) <= 0) || any(diff(ttlEphys) <= 0)
        error('Pulse times must be strictly increasing.');
    end

    %% Linear fit and residual check
    coef = polyfit(ttlBpod, ttlEphys, 1);
    residuals = ttlEphys - polyval(coef, ttlBpod);

    info.slope        = coef(1);
    info.offset       = coef(2);
    info.drift_ppm    = (coef(1) - 1) * 1e6;
    info.residual_rms = sqrt(mean(residuals.^2));
    info.residual_max = max(abs(residuals));
    info.n_pulses     = n;
    info.residuals    = residuals;

    fprintf(['Bpod -> ephys: offset %.3f ms, drift %.1f ppm, ' ...
        'residual rms %.3f ms, max %.3f ms (%d pulses)\n'], ...
        info.offset * 1e3, info.drift_ppm, info.residual_rms * 1e3, ...
        info.residual_max * 1e3, n);

    if info.residual_max > opt.MaxResidual
        warning(['Largest residual %.3f ms exceeds %.3f ms. Pulses may be ' ...
            'missing on one clock, or the wrong TTL line was used.'], ...
            info.residual_max * 1e3, opt.MaxResidual * 1e3);
    end

    %% Map times
    tOut = polyval(coef, tBpod);
    if strcmpi(opt.Method, 'interp')
        inside = tBpod >= ttlBpod(1) & tBpod <= ttlBpod(end);
        tOut(inside) = interp1(ttlBpod, ttlEphys, tBpod(inside), 'linear');
    end
    tOut = tOut + opt.Offset;
end
