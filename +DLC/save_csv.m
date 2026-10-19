function feedback = save_csv(filename, tabledlc)
%SAVE_CSV Write DLC-compatible CSV; absent likelihoods are explicitly unknown.
parts = tabledlc.Properties.UserData;
parts = cellstr(string(parts));
parts = parts(~strcmp(parts,'temp'));
if isempty(parts), error('DLC:save_csv:parts','No body parts are available to export.'); end
scorer = 'StepSync';
if isprop(tabledlc.Properties.CustomProperties,'Scorer') && ...
        ~isempty(tabledlc.Properties.CustomProperties.Scorer)
    scorer = char(tabledlc.Properties.CustomProperties.Scorer);
end
values = nan(height(tabledlc),3*numel(parts));
headers = cell(3,1+size(values,2));
headers(:,1) = {'scorer';'bodyparts';'coords'};
for k = 1:numel(parts)
    part = parts{k}; cols = 3*(k-1)+(1:3);
    names = {[part '_x'],[part '_y'],[part '_likelihood']};
    if ~all(ismember(names(1:2),tabledlc.Properties.VariableNames))
        error('DLC:save_csv:coordinates','Missing X/Y coordinates for %s.',part);
    end
    values(:,cols(1:2)) = tabledlc{:,names(1:2)};
    if ismember(names{3},tabledlc.Properties.VariableNames)
        values(:,cols(3)) = tabledlc.(names{3});
    end
    headers(1,cols+1) = repmat({scorer},1,3);
    headers(2,cols+1) = repmat({part},1,3);
    headers(3,cols+1) = {'x','y','likelihood'};
end
writecell(headers,filename,'Delimiter',',');
writematrix([(0:height(tabledlc)-1)' values],filename,'WriteMode','append','Delimiter',',');
feedback = 1;
end
