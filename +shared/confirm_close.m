function tf = confirm_close(fig, name)
% tf = shared.confirm_close(fig, name)
% Ask before closing a module window. No question while all windows close
% (Exit all, Load session).

    data = shared.SessionData.instance();
    tf = data.closingAll;
    if tf, return; end
    answer = uiconfirm(fig, sprintf('Close the %s?', name), 'Close', ...
        'Options', {'Close', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, ...
        'Icon', 'warning');
    tf = strcmp(answer, 'Close');
end
