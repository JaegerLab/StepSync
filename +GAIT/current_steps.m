function s = current_steps(data)
%CURRENT_STEPS Steps to display in other viewers, or [] when there are none.
%   s = GAIT.current_steps(data) returns a struct with fields
%       t    step times (s), row-aligned with idx
%       idx  frame indices of the selected step type
%       x, y paw position at each step, in pixels
%   for the paw, trace and step type selected in the gait viewer.
%   Returns [] when steps are not current for that selection or the
%   "Steps" checkbox is off. Viewers draw their own markers from this.
s = [];
if ~GAIT.steps_current(data), return; end
sel = data.gait.selection;
if ~sel.show, return; end
paw = data.gait.paw(sel.paw);
if ~isfield(paw, sel.step), return; end
idx = paw.(sel.step);
idx = idx(:);
s.idx = idx;
s.t = data.gait.t(idx);
s.t = s.t(:);
s.x = paw.raw_x(idx);
s.y = paw.raw_y(idx);
s.x = s.x(:);
s.y = s.y(:);
end
