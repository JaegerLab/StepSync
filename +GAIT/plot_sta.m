function ax = plot_sta(result, target)
% GAIT.plot_sta  Draw a Step-Triggered Average result into an axes.
%
%   ax = GAIT.plot_sta(result)          – result from GAIT.sta
%   ax = GAIT.plot_sta(result, target)  – target is axes or figure handle
%
%   Draws:
%     • Raw STA line (black solid)
%     • If there's control: dashed control-mean + shaded confidence interval
%     • Vertical centre line at t = 0
%     • Text labels at peak and trough times (relative to control mean)
%     • Legend
%
%   Normalization:
%     When result.normalize is true, display as pointwise z-score:
%       y_disp(t) = (y(t) - random_mean(t)) / random_std(t)
%     This collapses the control mean to 0 and CI to ± nStd for every method.
%
% See also: GAIT.sta

    %% ── Resolve target axes ──────────────────────────────────────────────
    if nargin < 2 || isempty(target) || isequal(target, false) || isequal(target, true)
        f  = figure();
        ax = axes(f);
    elseif isgraphics(target, 'axes')
        ax = target;
    elseif isgraphics(target, 'figure')
        ax = axes(target);
    else
        f  = figure();
        ax = axes(f);
    end

    %% ── Prepare display data (normalise if requested) ────────────────────
    t            = result.t(:);
    y            = result.y(:);
    rand_mean    = result.random_mean(:);
    rand_std     = result.random_std(:);
    nStd         = result.nStd;
    max_lag      = result.max_lag;
    doControl    = ~strcmp(result.method, 'none');
    is_global    = strcmp(result.method, 'global');
    normalize    = result.normalize && doControl;

    if normalize
        % Avoid divide-by-zero on flat std (should only happen if std==0 everywhere)
        safe_std = rand_std;
        safe_std(safe_std == 0) = 1;

        y_disp         = (y - rand_mean) ./ safe_std;
        rand_mean_disp = 0;           % collapses to 0
        rand_std_disp  = 1;            % collapses to 1
    else
        y_disp         = y;
        rand_mean_disp = rand_mean;
        rand_std_disp  = rand_std;
    end

    %% ── Draw ─────────────────────────────────────────────────────────────
    cla(ax);
    hold(ax, 'on');
    box(ax, 'off');

    % ── Control shading & mean (drawn first, so STA renders on top) ──────
    if doControl
        ci_upper = rand_mean_disp + nStd .* rand_std_disp;
        ci_lower = rand_mean_disp - nStd .* rand_std_disp;

        if is_global || normalize || isscalar(ci_upper) || isscalar(ci_lower)
            % Flat rectangle to reduce complexity of the graph
            fill_x = max_lag .* [-1 1 1 -1];
            fill_y = [ci_lower(1) ci_lower(1) ci_upper(1) ci_upper(1)];
            fill1  = fill(ax, fill_x, fill_y, ...
                'k', 'EdgeColor', 'none', 'FaceAlpha', 0.15, ...
                'DisplayName', sprintf('%d std CI (%.1f%%)', nStd, ci_pct(nStd)));
            line1  = yline(ax, rand_mean_disp(1), 'k--', ...
                'DisplayName', 'control mean');
        else
            % Curve-shaped fill
            fill_x = [t; flipud(t)];
            fill_y = [ci_upper; flipud(ci_lower)];
            fill1  = fill(ax, fill_x, fill_y, ...
                'k', 'EdgeColor', 'none', 'FaceAlpha', 0.15, ...
                'DisplayName', sprintf('%d std CI (%.1f%%)', nStd, ci_pct(nStd)));
            line1  = plot(ax, t, rand_mean_disp, 'k--', ...
                'DisplayName', 'control mean');
        end
        uistack(line1, 'down');
        uistack(fill1, 'bottom');
    end

    % ── STA line ──────────────────────────────────────────────────────────
    plot(ax, t, y_disp, 'k', 'DisplayName', 'STA');

    % ── Centre vertical line ──────────────────────────────────────────────
    xline(ax, 0, ':k', 'HandleVisibility', 'off');

    % ── Peak / trough text labels ─────────────────────────────────────────
    deviation = y_disp - rand_mean_disp;

    [~, idx_max] = max(deviation);
    text(ax, t(idx_max), y_disp(idx_max), ...
        sprintf('%.3f s', t(idx_max)), ...
        'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');

    [~, idx_min] = min(deviation);
    text(ax, t(idx_min), y_disp(idx_min), ...
        sprintf('%.3f s', t(idx_min)), ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'center');

    % ── Axis labels & legend ──────────────────────────────────────────────
    xlabel(ax, 't (s)');
    if normalize
        ylabel(ax, 'Amplitude (std)');
    else
        ylabel(ax, 'Amplitude');
    end

    if doControl
        legend(ax, 'Location', 'best');
    end

    hold(ax, 'off');
end

%% ── Helper: CI percentage for legend label ───────────────────────────────
function pct = ci_pct(n)
    % Approximate % of normal distribution within ±n sigma
    switch n
        case 1;  pct = 68.3;
        case 2;  pct = 95.5;
        case 3;  pct = 99.7;
        otherwise; pct = 100 * (erf(n/sqrt(2)));
    end
end
