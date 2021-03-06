function [isetObj,meshImage] = downloadPBRT( obj,varargin )
% Download data from gcloud bucket, returning *.dat files as ISET objects
% 
% Syntax:
%  gcp.downloadPBRT();
%  
% Input (required)
%   thisR:  A render recipe.
%    
% Inputs (optional)
%   scaleIlluminance -  if true, we scale the mean illuminance by the pupil
%                       diameter in piDat2ISET 
%
% Return
%  isetObj - a cell array of ISET scene or oi (depending on the recipe
%            optics)
%
% TL/ZL, Vistalab 2017
%
% See also: piDat2ISET

%%
p = inputParser;

varargin = ieParamFormat(varargin);

p.addRequired('thisR',@(x)(isequal(class(x),'recipe') || ischar(x)));

p.addParameter('scaleIlluminance',true,@islogical);

p.parse(thisR,varargin{:});
scaleIlluminance = p.Results.scaleIlluminance;

%%

isetObj = cell(1,length(obj.targets));

% We return a file for each of the gcloud targets
for t=1:length(obj.targets)
    
    if(obj.targets(t).depthFlag)
        % We skip the depth map for now. Later when we encounter a radiance
        % target we will look for the corresponding depth map and load it
        % then. See below.
        continue;
    end
        
    % This is where the data started
%     [targetFolder]  = fileparts(thisR.get('outputfile'));
    [targetFolder]= fileparts(obj.targets(t).local);
    % The targets slot contains the fullpath to the output on the
    % cloud
    [remoteFolder, remoteFile] = fileparts(obj.targets(t).remote);
    
    % Command to download from cloud to local directory
    cmd = sprintf('gsutil cp %s/renderings/%s.dat %s/renderings/%s.dat',...
        remoteFolder,remoteFile,targetFolder,remoteFile);
    
    % Do it
    [status, result] = system(cmd);
    if status
        disp(result)
    end
    
    % Convert the dat file to an ISET format
    outFile = sprintf('%s/renderings/%s.dat',targetFolder,remoteFile);
    
    % Convert radiance to optical image
    ieObject = piDat2ISET(outFile,...
        'label','radiance',...
        'recipe',thisR,...
        'scaleIlluminance',scaleIlluminance);
    
    % Look for the corresponding depth file (if necessary)
    if(obj.renderDepth)
        cmd = sprintf('gsutil cp %s/renderings/%s_depth.dat %s/renderings/%s_depth.dat',...
            remoteFolder,remoteFile,targetFolder,remoteFile);
        
        % Do it
        [status, result] = system(cmd);
        if status
            disp(result)
            warning('Could not download depth map: %s/renderings/%s_depth.dat',remoteFolder,remoteFile);
        end
        
        % Read the downloaded depth file
         depthOutFile = sprintf('%s/renderings/%s_depth.dat',targetFolder,remoteFile);

         depthMap = piReadDAT(depthOutFile, 'maxPlanes', 31);
         depthMap = depthMap(:,:,1);
    end
    % Look for the corresponding mesh file (if necessary)
    if(obj.renderMesh)
        cmd = sprintf('gsutil cp %s/renderings/%s_mesh.dat %s/renderings/%s_mesh.dat',...
            remoteFolder,remoteFile,targetFolder,remoteFile);
        
        % Do it
        [status, result] = system(cmd);
        if status
            disp(result)
            warning('Could not download mesh image: %s/renderings/%s_mesh.dat',remoteFolder,remoteFile);
        end
        
        cmd = sprintf('gsutil cp %s/renderings/%s_mesh_mesh.txt %s/renderings/%s_mesh.txt',...
            remoteFolder,remoteFile,targetFolder,remoteFile);
        
        % Do it
        [status, result] = system(cmd);
        if status
            disp(result)
            warning('Could not download mesh image: %s/renderings/%s_mesh_mesh.txt',remoteFolder,remoteFile);
        end
        
        % Read the downloaded depth file
        meshOutFile = sprintf('%s/renderings/%s_mesh.dat',targetFolder,remoteFile);
        meshData = piReadDAT(meshOutFile, 'maxPlanes', 31);
        meshImage{t} = meshData(:,:,1); % directly output a meshImage?
    end
    
    % Convert the dat file to an ISET format
    outFile = sprintf('%s/renderings/%s.dat',targetFolder,remoteFile);
    
    % This code should be a separate function, and be shared with
    % piRender.
    if exist(outFile,'file')
    photons = piReadDAT(outFile, 'maxPlanes', 31);
    
    ieObjName = sprintf('%s-%s',remoteFile,datestr(now,'mmm-dd,HH:MM'));
    if strcmp(obj.targets(t).camera.subtype,'perspective')
        opticsType = 'pinhole';
    else
        opticsType = 'lens';
    end
    
    % If radiance, return a scene or optical image
    switch opticsType
        case 'lens'
            % If we used a lens, the ieObject is an optical image (irradiance).
            
            % We should set fov or filmDiag here.  We should also set other ray
            % trace optics parameters here. We are using defaults for now, but we
            % will find those numbers in the future from inside the radiance.dat
            % file and put them in here.
            ieObject = piOICreate(photons,varargin{:});  % Settable parameters passed
            ieObject = oiSet(ieObject,'name',ieObjName);
            % I think this should work (BW)
            if exist('depthMap','var')
            if(~isempty(depthMap))
                ieObject = oiSet(ieObject,'depth map',depthMap);
            end
            end
            
            % This always worked in ISET, but not in ISETBIO.  So I stuck in a
            % hack to ISETBIO to make it work there temporarily and created an
            % issue. (BW).
            ieObject = oiSet(ieObject,'optics model','ray trace');
            
        case 'pinhole'
            % In this case, we the radiance describes the scene, not an oi
            ieObject = piSceneCreate(photons,'meanLuminance',1000);
            ieObject = sceneSet(ieObject,'name',ieObjName);
            if exist('depthMap','var')
            if(~isempty(depthMap))
                ieObject = sceneSet(ieObject,'depth map',depthMap);
            end
            end
            
            % There may be other parameters here in this future
            if strcmp(obj.targets(t).camera.subtype,'perspective')
                ieObject = sceneSet(ieObject,'fov',obj.targets(t).camera.fov.value);
            end
    end
    else
        ieObject = [];
    end
    isetObj{t} = ieObject;
    
end

% Clear empty cells in isetObj that were created from depth map targets
if(obj.renderDepth)
    isetObj = isetObj(~cellfun('isempty',isetObj)) ;
end

if (obj.renderMesh)
    meshImage = meshImage(~cellfun('isempty',meshImage));
end

end

