function gait = gait_analysis_headfix(varargin) %#ok<STOUT,INUSD>
%GAIT_ANALYSIS_HEADFIX Reserved legacy entry point, not a supported batch API.
% Head-fixed analysis is currently implemented in GAIT.gait_viewer.
error('GAIT:headfix:notImplemented', ...
    'Use GAIT.gait_viewer for head-fixed analysis. The batch API is not implemented.');
end
