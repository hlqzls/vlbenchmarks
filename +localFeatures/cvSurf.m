% CVSURF feature extractor wrapper of OpenCV SURF detector
%
% Feature Extractor wrapper around the OpenCV SURF detector. This class
% constructor accepts the same options as <a href="matlab: help localFeatures.mex.cvSurf">localFeatures.mex.cvSurf</a>
%


classdef cvSurf < localFeatures.genericLocalFeatureExtractor & ...
    helpers.GenericInstaller
  properties (SetAccess=public, GetAccess=public)
    cvsurf_argument
    binPath
  end

  methods

    function obj = cvSurf(varargin)
      obj.detectorName = 'OpenCV SURF';
      obj.cvsurf_argument = obj.configureLogger(obj.detectorName,varargin);
      if ~obj.isInstalled()
        obj.warn('Not installed.')
        obj.installDeps();
      end
      
      obj.binPath = {which('localFeatures.mex.cvSurf')};
    end

    function [frames descriptors] = extractFeatures(obj, imagePath)
      import helpers.*;
      
      [frames descriptors] = obj.loadFeatures(imagePath,nargout > 1);
      if numel(frames) > 0; return; end;
      
      startTime = tic;
      if nargout == 1
        obj.info('Computing frames of image %s.',getFileName(imagePath));
      else
        obj.info('Computing frames and descriptors of image %s.',getFileName(imagePath));
      end
      
      img = imread(imagePath);
      if(size(img,3)>1), img = rgb2gray(img); end
      img = uint8(img); % If not already in uint8, then convert
      
      if nargout == 2
        [frames descriptors] = localFeatures.mex.cvSurf(img,obj.cvsurf_argument{:});
      elseif nargout == 1
        [frames] = localFeatures.mex.cvSurf(img,obj.cvsurf_argument{:});
      end
      
      timeElapsed = toc(startTime);
      obj.debug('Frames of image %s computed in %gs',...
        getFileName(imagePath),timeElapsed);
      
      obj.storeFeatures(imagePath, frames, descriptors);
    end
    
    function sign = getSignature(obj)
      sign = [helpers.fileSignature(obj.binPath{:}) ';'...
              helpers.cell2str(obj.cvsurf_argument)];
    end
  end
  
  methods (Static)
    function deps = getDependencies()
      deps = {helpers.Installer() helpers.VlFeatInstaller() helpers.OpenCVInstaller()};
    end
    
    function [srclist flags] = getMexSources()
      import helpers.*;
      path = fullfile(pwd,'+localFeatures','+mex','');
      srclist = {fullfile(path,'cvSurf.cpp')};
      flags = {[OpenCVInstaller.MEXFLAGS ' ' VlFeatInstaller.MEXFLAGS ]};
    end
  end
end
