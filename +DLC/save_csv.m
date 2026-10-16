function feedback = save_csv(filename, tabledlc)



try
    feedback = 0;
    % write headers
    lines = ['scorer', repmat({tabledlc.Properties.Description}, 1, width(tabledlc)); ...
            'bodyparts', repelem(tabledlc.Properties.UserData, 1, 3); ...
            'coords', repmat({'x','y','likelihood'},1,length(tabledlc.Properties.UserData))];
    writecell(lines , filename, 'Delimiter',',');
    
    % write table
    index = (0:height(tabledlc)-1)';
    tabledlc = addvars(tabledlc, index, 'Before', 1);
    writetable(tabledlc, filename, 'WriteMode','append', 'Delimiter',',');
    feedback=1; %success
catch ME
    rethrow(ME)
end
