classdef SessionData < handle
    properties
        fig struct
        video struct
        pose struct
        ephys struct
        gait struct

        frameRate double = 0;
        currentTime double = 0;
        currentZoom double = [0 10];

        defaultPath char = '';      % start folder of file dialogs
        closingAll logical = false; % true while all windows close: no prompts, no reset
    end

    events
        TimeChanged         % currentTime moved
        ZoomChanged         % currentZoom moved
        InfoChanged         % time base changed: frame rate, triggers, frame count
        EphysChanged          % ephys traces changed (open, pre-process, delete)
        PoseChanged          % pose table or selection changed; carries shared.PoseChangedData
        GaitChanged         % gait results changed: steps, selection, visibility
        MaskChanged         % gait mask committed: gait recalculates steps
        MaskPreviewChanged  % gait mask preview: gait redraws trace colours only
        WindowsChanged      % a module window or sub-window opened or closed
    end

    properties (Access = private)
        warningState   % restored when the session ends
    end

    methods (Access = private)
        % hide constructor as private to avoid creating multiple instances
        function obj = SessionData()
            % Turn off the "ButtonDownFcn" warning when selecting axes tools,
            % for as long as the session lives: it ends with Exit all or when
            % the last module window closes, not when one of several closes.
            obj.warningState = warning('off', 'MATLAB:modes:mode:InvalidPropertySet');
        end
    end

    methods (Static)
        % use static function to ensure sharing data with 1 instance.
        function obj = instance()
            persistent singleton
            if isempty(singleton) || ~isvalid(singleton)
                singleton = shared.SessionData();
            end
            obj = singleton;
        end
    end

    methods
        function delete(obj)
            if ~isempty(obj.warningState), warning(obj.warningState); end
        end

        function setTime(obj, t)
            if obj.currentTime ~= t
                obj.currentTime = t;
                notify(obj, 'TimeChanged');
            end
        end

        function setZoom(obj, xlims)
            if ~isequal(obj.currentZoom, xlims)
                obj.currentZoom = xlims;
                notify(obj, 'ZoomChanged');
            end
        end

        % A typed-in rate overrides the automatic one; [] or 0 returns to automatic.
        function setFrameRate(obj, value)
            if isempty(value), value = 0; end
            validateattributes(value, {'numeric'}, {'scalar','real','finite','nonnegative'});
            obj.frameRate = double(value);
            notify(obj, 'InfoChanged');
            notify(obj, 'TimeChanged');
        end

        % Manual override > valid camera TTL rate > video rate > frame units.
        %   source: 'manual' | 'trigger' | 'video' | 'none'
        function [frameRate, source] = getFrameRate(obj)
            frameRate = obj.frameRate;
            source = 'manual';
            if isscalar(frameRate) && isfinite(frameRate) && frameRate > 0, return; end
            % the trigger counts even when all ephys data was deleted
            source = 'trigger';
            if isfield(obj.ephys, 'trigger') && isfield(obj.ephys.trigger, 'freq')
                frameRate = obj.ephys.trigger.freq;
                if isscalar(frameRate) && isfinite(frameRate) && frameRate > 0, return; end
            end
            if obj.has('video')
                frameRate = obj.video.vid.FrameRate;
                source = 'video';
            else
                frameRate = 1;
                source = 'none';
            end
        end

        % Trigger times while the trigger sets the rate; a typed-in rate
        % overrides them too (e.g. when the triggers are wrong).
        function t = getFrameTimes(obj, nFrames)
            [frameRate, source] = obj.getFrameRate();
            triggers = [];
            if strcmp(source, 'trigger') && isfield(obj.ephys.trigger, 'time') && ...
                    numel(obj.ephys.trigger.time) >= 2
                triggers = obj.ephys.trigger.time;
            end
            t = shared.frame_times(nFrames, frameRate, triggers);
        end

        % Frame counts of the open frame-based data, by module.
        function counts = frameCounts(obj)
            counts = struct();
            if obj.has('video'), counts.video = obj.video.vid.NumFrames; end
            if obj.has('pose'), counts.pose = height(obj.pose.table); end
            if obj.has('gait'), counts.gait = numel(obj.gait.paw(1).rawX); end
        end

        % Notify PoseChanged with what changed.
        %   kind: 'open' | 'edit' | 'commit' | 'preview' | 'selection' | 'close' | 'load'
        %   bodyparts: cellstr of changed body parts (may be empty)
        function notifyPose(obj, kind, bodyparts)
            if nargin < 3, bodyparts = {}; end
            notify(obj, 'PoseChanged', shared.PoseChangedData(kind, bodyparts));
        end

        % Remember the folder of a file or folder opened or saved in a module.
        function rememberPath(obj, fileOrFolder)
            folder = fileOrFolder;
            if ~isfolder(folder), folder = fileparts(fileOrFolder); end
            if ~isempty(folder) && isfolder(folder), obj.defaultPath = folder; end
        end

        % Called by a module window after it closed. Closing the last module
        % window resets the session, unless all windows are being closed.
        function moduleClosed(obj)
            notify(obj, 'WindowsChanged');
            if obj.closingAll, return; end
            modules = fieldnames(obj.fig);
            for k = 1:numel(modules)
                if isgraphics(obj.fig.(modules{k}), 'figure'), return; end
            end
            delete(obj);
        end

        % check if data section is available
        function tf = has(obj, objectName)
            tf = false;
            switch lower(objectName)
                case 'video'
                    if ~isempty(obj.video) && isfield(obj.video, 'vid') && ~isempty(obj.video.vid)
                        tf = true;
                    end
                case 'ephys'
                    % raw or any processed data; metadata alone does not count
                    tf = ~isempty(obj.ephys) && ~isempty(ephys.ephys_types(obj.ephys)); %#ok<PROPLC> package
                case 'pose'
                    if ~isempty(obj.pose) && isfield(obj.pose, 'table') && ~isempty(obj.pose.table)
                        tf = true;
                    end
                case 'gait'
                    if ~isempty(obj.gait) && isfield(obj.gait, 'paw') && ~isempty(obj.gait.paw)
                        tf = true;
                    end
                case 'bpod'

                otherwise
                    tf = false;
            end
        end

    end
end
