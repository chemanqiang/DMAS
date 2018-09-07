% RUN_TRACKER: process a specified video using CF2
%
% Input:
%     - video:              the name of the selected video
%     - show_visualization: set to True for visualizing tracking results
%     - show_plots:         set to True for plotting quantitative results
% Output:
%     - precision:          precision thresholded at 20 pixels
%
% 
function run_tracker(video, show_visualization, show_plots)

%path to the videos (you'll be able to choose one with the GUI).
base_path   = '/opt/dataset/otb100/';
addpath('utility','model','external/matconvnet/matlab','scale');
st=1;
md=2;
vl_setupnn();
% Default settings
if nargin < 1, video = 'choose'; end
if nargin < 2, show_visualization = ~strcmp(video, 'all'); end
if nargin < 3, show_plots = ~strcmp(video, 'all'); end
% Extra area surrounding the target
padding = struct('generic', 1.8, 'large', 1, 'height', 0.8);
lambda = 1e-4;              % Regularization parameter (see Eqn 3 in our paper)
output_sigma_factor =0.1;  %sigma;  % Spatial bandwidth (proportional to the target size)
interp_factor = 0.01;       % Model learning rate (see Eqn 6a, 6b)
cell_size = 4;              % Spatial cell size

global enableGPU;
enableGPU = true;

switch video
    case 'choose',
        % Ask the user for selecting the video, then call self with that video name.
        video = choose_video(base_path);
        if ~isempty(video)
            % Start tracking   [precision, fps]
             [img_files, pos, target_sz, ground_truth, video_path] = load_video_info(base_path, video);
            [positions, time] = tracker_ensemble(video_path, img_files, pos, target_sz, ...
    padding, lambda, output_sigma_factor, interp_factor, cell_size, show_visualization,st,md);
            close;
        % Calculate and show precision plot, as well as frames-per-second
        precisions = precision_plot(positions(:,1:2), ground_truth, video, show_plots);
        fps = numel(img_files) / time;
        fprintf('%12s - Precision (20px):% 1.3f, FPS:% 4.2f\n', video, precisions(20), fps)                   
        end
        
    case 'all',
        %all videos, call self with each video name.
        if ispc(), base_path = strrep(base_path, '\', '/'); end
        if base_path(end) ~= '/', base_path(end+1) = '/'; end
	
        %list all sub-folders
        contents = dir(base_path);
        names = {};
        for k = 1:numel(contents),
		name = contents(k).name;
		if isdir([base_path name]) && ~any(strcmp(name, {'.', '..'})),
			names{end+1} = name;  %#ok
        end
        end
        show_visualization=0;
        show_plots=0;
        results = cell(1,length(names));
        for k=1:length(names)
             video=names{k};
             if ~isempty(video)
            % Start tracking   [precision, fps]
            [img_files, pos, target_sz, ground_truth, video_path] = load_video_info(base_path, video);
            [positions, time] = tracker_ensemble(video_path, img_files, pos, target_sz, ...
    padding, lambda, output_sigma_factor, interp_factor, cell_size, show_visualization,st,md);
            close;
        % Calculate and show precision plot, as well as frames-per-second
            precisions = precision_plot(positions(:,1:2), ground_truth, video, show_plots);
            fps = numel(img_files) / time;
        
           fprintf('%12s - Precision (20px):% 1.3f, FPS:% 4.2f\n', video, precisions(20), fps)
        
           rect_position= [positions(:,2)-positions(:,4)/2, positions(:,1)-positions(:,3)/2,positions(:,[4,3])];

         results{k}.type = 'rect';
        results{k}.res = rect_position;%each row is a rectangle
        results{k}.fps = fps; 
        results{k}.len = length(img_files);
        results{k}.annoBegin=1;
        results{k}.startFrame=1;    
             end
        end
        save(['result//' 'seleMlaupscale111111.mat'],'results');
       
end
