function tabledlc = read_csv (filename)
% read csv format created by DeepLabCut
% Li Su, 2023/12/18
% The zero-based index column is kept as 1-based frame numbers in
% tabledlc.Properties.CustomProperties.FrameIndex; a file cropped by
% StepSync starts after frame 1 (see DLC.align_frames).

opts = delimitedTextImportOptions;
opts.DataLines = [1 3];
txt = readmatrix(filename,opts);
headers = genvarname(strcat(txt(2,:), {'_'}, txt(3,:)));

% read data
tabledlc=readtable(filename, 'Headerlines',3);

% the first column holds frame indices if its header is 'coords'
frames = (1:height(tabledlc))';
if isequal(txt{3,1},'coords')
    frames = tabledlc{:,1} + 1;
    tabledlc(:,1)=[];
    headers(1)=[];
    txt(:,1)=[];
end

tabledlc.Properties.VariableNames = headers;
tabledlc.Properties.UserData = unique(txt(2,:),'stable'); %bodyparts
tabledlc.Properties.Description = filename; %source filename
tabledlc = addprop(tabledlc,{'Scorer','FrameIndex'},{'table','table'});
tabledlc.Properties.CustomProperties.Scorer = txt{1,1};
tabledlc.Properties.CustomProperties.FrameIndex = frames;
