function tf = confirm_close(fig, module)
% tf = shared.confirm_close(fig, module)
% Ask before closing a module window ('video', 'ephys', 'pose' or 'gait').
% No question while all windows close (Exit all, Load session) or when the
% module has no data. Ephys data whose types were all deleted still counts
% while its camera trigger is kept.

    data = shared.SessionData.instance();
    tf = data.closingAll || ~(data.has(module) || ...
        (strcmp(module, 'ephys') && isfield(data.ephys, 'trigger')));
    if tf, return; end
    name = ['StepSync ' upper(module(1)) module(2:end)];
    answer = uiconfirm(fig, sprintf('Close %s?', name), 'Close', ...
        'Options', {'Close', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, ...
        'Icon', 'warning');
    tf = strcmp(answer, 'Close');
end
