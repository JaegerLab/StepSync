classdef SessionData < handle
    properties
        fig struct
        video struct
        dlc struct
        emg struct
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
        EMGChanged          % EMG traces changed (open, pre-process, delete)
        DLCChanged          % DLC table or selection changed; carries shared.DLCChangedData
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

        function setFrameRate(obj, value)
            validateattributes(value, {'numeric'}, {'scalar','real','finite','positive'});
            obj.frameRate = double(value);
            notify(obj, 'InfoChanged');
            notify(obj, 'TimeChanged');
        end

        % Manual override > valid camera TTL rate > video rate > frame units.
        function frameRate = getFrameRate(obj)
            frameRate = obj.frameRate;
            if isscalar(frameRate) && isfinite(frameRate) && frameRate > 0, return; end
            if obj.has('emg') && isfield(obj.emg, 'trigger') && ...
                    isfield(obj.emg.trigger, 'freq')
                frameRate = obj.emg.trigger.freq;
                if isscalar(frameRate) && isfinite(frameRate) && frameRate > 0, return; end
            end
            if obj.has('video')
                frameRate = obj.video.vid.FrameRate;
            else
                frameRate = 1;
            end
        end

        function t = getFrameTimes(obj, nFrames)
            triggers = [];
            if obj.has('emg') && isfield(obj.emg, 'trigger') && ...
                    isfield(obj.emg.trigger, 'time') && numel(obj.emg.trigger.time) >= 2
                triggers = obj.emg.trigger.time;
            end
            t = shared.frame_times(nFrames, obj.getFrameRate(), triggers);
        end

        % Notify DLCChanged with what changed.
        %   kind: 'open' | 'edit' | 'commit' | 'preview' | 'selection' | 'close' | 'load'
        %   bodyparts: cellstr of changed body parts (may be empty)
        function notifyDLC(obj, kind, bodyparts)
            if nargin < 3, bodyparts = {}; end
            notify(obj, 'DLCChanged', shared.DLCChangedData(kind, bodyparts));
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
                case 'emg'
                    if ~isempty(obj.emg) && isfield(obj.emg, 'analog_data') && ~isempty(obj.emg.analog_data)
                        tf = true;
                    end
                case 'dlc'
                    if ~isempty(obj.dlc) && isfield(obj.dlc, 'table') && ~isempty(obj.dlc.table)
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
