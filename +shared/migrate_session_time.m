function saved = migrate_session_time(saved)
%MIGRATE_SESSION_TIME Upgrade pre-TTL session clocks without moving frame masks.
if isfield(saved,'timebaseVersion') && saved.timebaseVersion >= 2, return; end
% Earlier DLC speed snapshots stored cm/s on a frozen timestamp grid.
if isfield(saved,'gait') && isfield(saved.gait,'maskParam')
    p = saved.gait.maskParam;
    if isfield(p,'SpeedSource') && startsWith(string(p.SpeedSource),'DLC:') && ...
            ~isfield(p,'SpeedUnits') && isfield(saved.gait,'speedFactor') && ...
            isfinite(saved.gait.speedFactor) && saved.gait.speedFactor>0
        p.Speed = p.Speed/saved.gait.speedFactor;
        p.SpeedTime = [];
        p.SpeedUnits = 'pixels/frame';
        saved.gait.maskParam = p;
    end
end
if ~isfield(saved,'emg') || ~isfield(saved.emg,'trigger') || ...
        ~isfield(saved.emg.trigger,'time') || numel(saved.emg.trigger.time)<2
    saved.timebaseVersion = 2; return;
end
ttl = saved.emg.trigger.time(:);
validateattributes(ttl,{'numeric'},{'vector','finite','increasing'});
fps = saved.frameRate;
if ~isfinite(fps) || fps<=0, fps = 1/median(diff(ttl)); end
oldGrid = (1:numel(ttl))'/fps;
convert = @(t)interp1(oldGrid,ttl,t,'linear','extrap');
saved.currentTime = max(0,convert(saved.currentTime));
saved.currentZoom = convert(saved.currentZoom);
if isfield(saved,'gait') && isfield(saved.gait,'maskParam') && ...
        isfield(saved.gait.maskParam,'Rules')
    rules = saved.gait.maskParam.Rules;
    rules.FromTime = convert(rules.FromTime);
    rules.ToTime = convert(rules.ToTime);
    saved.gait.maskParam.Rules = rules;
end
if isfield(saved,'gait') && isfield(saved.gait,'sta') && ~isempty(saved.gait.sta)
    warning('StepSync:timing:legacySTA', ...
        'Stored STA curves used the old frame clock. Rerun them for TTL-corrected alignment.');
end
saved.timebaseVersion = 2;
end
