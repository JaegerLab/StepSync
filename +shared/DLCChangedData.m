classdef DLCChangedData < event.EventData
%DLCCHANGEDDATA Event data for SessionData's DLCChanged event.
%   Kind      - what happened to the DLC data:
%       'open'      a new DLC file replaced the table (all body parts changed)
%       'edit'      committed coordinates of existing body parts were edited
%       'commit'    a fix was committed as a body part (new or overwritten)
%       'delete'    a body part was deleted
%       'preview'   only temporary fix-preview columns changed
%       'selection' the selected body part changed; the data did not
%       'close'     the DLC viewer closed and its data was cleared
%       'load'      a session restored the DLC data
%   Bodyparts - cellstr of the body parts whose committed data changed.
    properties
        Kind char
        Bodyparts cell
    end

    methods
        function obj = DLCChangedData(kind, bodyparts)
            if nargin < 2 || isempty(bodyparts), bodyparts = {}; end
            obj.Kind = char(kind);
            obj.Bodyparts = cellstr(string(bodyparts));
        end
    end
end
