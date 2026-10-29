function tablePose = read_csv (filename)
% read csv format created by DeepLabCut
% Li Su, 2023/12/18
% The zero-based index column is kept as 1-based frame numbers in
% tablePose.Properties.CustomProperties.FrameIndex; a file cropped by
% StepSync starts after frame 1 (see pose.align_frames).

opts = delimitedTextImportOptions;
opts.DataLines = [1 3];
txt = readmatrix(filename,opts);
headers = genvarname(strcat(txt(2,:), {'_'}, txt(3,:)));

% read data
tablePose=readtable(filename, 'Headerlines',3);

% the first column holds frame indices if its header is 'coords'
frames = (1:height(tablePose))';
if isequal(txt{3,1},'coords')
    frames = tablePose{:,1} + 1;
    tablePose(:,1)=[];
    headers(1)=[];
    txt(:,1)=[];
end

tablePose.Properties.VariableNames = headers;
tablePose.Properties.UserData = unique(txt(2,:),'stable'); %bodyparts
tablePose.Properties.Description = filename; %source filename
tablePose = addprop(tablePose,{'Scorer','FrameIndex'},{'table','table'});
tablePose.Properties.CustomProperties.Scorer = txt{1,1};
tablePose.Properties.CustomProperties.FrameIndex = frames;
