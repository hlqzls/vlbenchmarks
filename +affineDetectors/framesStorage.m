classdef framesStorage < handle
  %FRAMESSTORAGE Class for storing calculated frames.
  %   framesStorage(dataset, 'OptionName',optionValue,...) 
  %   constructs new frameStorage object for calculating frames on
  %   particular dataset using set of affine frame detectors.
  %   
  %   To add detectors call addDetectors. This method can be called on already
  %   constructed objects therefore addin new detectors. Removing detectors
  %   is not supported.
  %
  %   This class implements caching results from previous runs and
  %   therefore speeding up the test calculation for example when
  %   parameters only of some detectors changed. This is basically done by
  %   introducing signatures which specify states of the detectors and
  %   input data.
  %
  %   Information tracked usually in the signatures are last modification
  %   dates of files, binaries and list of option values.
  %
  %   Options:
  %
  %   CalcDescriptors :: [true]
  %   Calculates descriptors of frames when supported by the frames
  %   detector.
  %
  
  
  properties (SetAccess=protected, GetAccess=public)
    detectors = {};           % List of added detectors
    detectorsNames = {};      % Names of the detectors
    dataset                   % Dataset for which the frames are calculated.
    frames = {};              % Cached detected frames.
    descriptors = {};         % Cached detected frames descriptors.
    images                    % Images data.
    tfs                       % Transformation between images.
    opts                      % Options
    det_signatures = {};      % Last signatures of the detectors.
    dataset_signature = '';   % Last signature of the dataset.
    det_names;                % List of classes of the detectors
    
  end
  
  methods
    function obj=framesStorage(dataset,varargin)
      obj.dataset = dataset;
      
      obj.opts.calcDescriptors = true;
      
      if numel(varargin) > 0
        obj.opts = vl_argparse(obj.opts, varargin);
      end
      
      assert(isa(dataset,'affineDetectors.genericDataset'),...
          'dataset not an instance of generic dataset\n');
    end
    
    function calcFrames(obj)
      % CALCFRAMES Recalculate the frames when needed.
      cur_dataset_sign = obj.dataset.signature();
      newDataset = ~isequal(cur_dataset_sign, obj.dataset_signature);
      numDetectors = numel(obj.detectors);
      detNames = obj.detectorsNames;
      
      fprintf('Detecting affine covariant frames using %d detectors\n',numDetectors);
      
      if newDataset
        % -------- Load the dataset ---------------------------
        fprintf(['\nLoading dataset ',obj.dataset.datasetName]);
        numImages = obj.dataset.numImages;
        obj.images = cell(1,numImages);
        imagePaths = cell(1,numImages);
        for i=1:numImages
          imagePaths{i} = obj.dataset.getImagePath(i);
          obj.images{i} = imread(imagePaths{i});
          obj.tfs{i} = obj.dataset.getTransformation(i);
        end  
     
        fprintf('Loaded %d images.\n',numImages);
      end
      
      obj.dataset_signature = cur_dataset_sign;
      
      detectors = obj.detectors;
      det_signatures = obj.det_signatures;
      frames = obj.frames;
      descriptors = obj.descriptors;
      
      parfor det_i = 1:numDetectors
        detector = detectors{det_i};
        det_sign = detector.signature();
        if newDataset || ~isequal(det_sign, det_signatures{det_i})
          fprintf('\nComputing affine covariant regions for method: %s\n\n', ...
                detNames{det_i});
          [curFrames curDescriptors] = obj.runDetector(detector);
          frames{det_i} = curFrames;
          descriptors{det_i} = curDescriptors;
          det_signatures{det_i} = detector.signature();
        else
          fprintf('\nAffine covariant frames of method %s are up to date.\n', ...
                detNames{det_i});
        end;
      end
      
      obj.detectors = detectors;
      obj.det_signatures = det_signatures;
      obj.frames = frames;
      obj.descriptors = descriptors;
      
      % -------- Output which detectors didn't work ------
      for i = 1:numel(obj.detectors),
        if ~obj.detectors{i}.isOk,
          fprintf('Detector %s failed because: %s\n',...
                  obj.detectors{i}.getName(),...
                  obj.detectors{i}.errMsg);
        end
      end
      
      fprintf('\n------ Affine covariant frames computed ---------\n');
      
    end
    
    
    function addDetectors(obj, detectors, remove_duplicates)
      % ADDDETECTORS(detectors) Adds new detectors. Detectors is cell of
      % detectors objects.
      % Does not support more detectors of one class.
      numDetectors = numel(detectors);
      
      if nargin == 2
        remove_duplicates = true;
      end
      
      for i=1:numDetectors
        det_name = detectors{i}.detectorName;
        [is_memb det_idx] = ismember(det_name, obj.det_names);
        if sum(is_memb)==0 || ~remove_duplicates
          obj.detectors{end+1} = detectors{i};
          obj.det_names{end+1} = det_name;
          obj.frames{end+1} = [];
          obj.detectorsNames{end+1} = detectors{i}.detectorName;
          obj.det_signatures{end+1} = '';
        else
          obj.detectors{det_idx} = detectors{i};
        end
      end
    end
    
    function numdet = numDetectors(obj)
      numdet = numel(obj.detectors);
    end
    
    function numimages = numImages(obj)
      numimages = obj.dataset.numImages;
    end
    
  end
  
  methods (Access=protected)
    
    function [frames descriptors] = runDetector(obj, detector)
      % RUNDETECTOR Recalculate frames of particular detector.
        assert(isa(detector,'affineDetectors.genericDetector'),...
         'Detector not an instance of genericDetector\n');
        numImages = obj.dataset.numImages;
        images = obj.images;
        
        frames = cell(1,numImages);
        descriptors = cell(1,numImages);

        if(~detector.isOk)
          fprintf('Detector: %s is not working, message: %s\n', ...
                  detector.getName(), detector.errMsg);
          frames = {};
          descriptors = {};
          return;
        end

        calcDescriptors = obj.opts.calcDescriptors;
        canCalcDescriptors = detector.calcDescs;
        
        parfor i = 1:numImages
          fprintf('\tComputing regions for image: %02d/%02d ...',i,numImages);
          if calcDescriptors
            if canCalcDescriptors
              [curFrames curDescriptors] = detector.detectPoints(images{i});
            else
              [detFrames] = detector.detectPoints(images{i});
              fprintf('\n\t\tComputing SIFT descriptors of %d frames...',size(frames{i},2));
              % TODO solve how to do this with orientation - shall it be
              % calculated for the descriptors? Depends for the type of the
              % dataset...
              [curFrames curDescriptors] = ...
                affineDetectors.helpers.calcSiftDesc(images{i}, detFrames, true);
            end
          else
            curFrames{i} = detector.detectPoints(images{i});
            curDescriptors = [];
          end
          frames{i} = curFrames;
          descriptors{i} = curDescriptors;
          fprintf(' (%d regions detected)\n',size(curFrames,2));
        end
        
    end
    
    function plotDataset(obj)
      numImages = numel(obj.images);
      numCols = ceil(sqrt(numImages));
      numRows = ceil(numImages/numCols);

      for i = 1:numImages
        %colNo = 1+mod(i-1,numCols);
        %rowNo = 1+floor((i-1)/numCols);
        %subplot(numRows,numCols,(colNo-1)*numRows+rowNo);
        subplot(numRows,numCols,i);
        imshow(obj.images{i}); title(sprintf('Image #%02d',i));
      end
      drawnow;
    end
    
  end
  
end

