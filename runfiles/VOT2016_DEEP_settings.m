function results = VOT2016_DEEP_settings()
% Extra area surrounding the target
% 	padding = struct('generic',1.8, 'large', 1,'height',0.8);
% 	lambda = 1e-4;              % Regularization parameter (see Eqn 3 in our paper)
% 	output_sigma_factor = 0.1;  % Spatial bandwidth (proportional to the target size)
% 	interp_factor = 0.01;       % Model learning rate (see Eqn 6a, 6b)
% 	cell_size =4;              % Spatial cell size
% 	global enableGPU;
% 	enableGPU = true;
%     show_visualization=0;
% 	video_path='';
%     % Get sequence info
% [seq, im] = get_sequence_info(seq);
% if isempty(im)
%     seq.rect_position = [];
%     [seq, results] = get_sequence_results(seq);
%     return;
% end
% fid = fopen('images.txt','r'); 
% images = textscan(fid, '%s', 'delimiter', '\n');
% fclose(fid);
% images = images{1};
%         img_files=images;
%        pos = seq.init_pos(:)';
%        target_sz = seq.init_sz(:)';
% %     [img_files, pos, target_sz] = load_video_info_vot(video_path, seq);
[images, region] = vot_tracker_initialize();
vl_setupnn();
padding = struct('generic', 1.8, 'large', 1, 'height', 0.8);
lambda = 1e-4;              % Regularization parameter (see Eqn 3 in our paper)
output_sigma_factor =0.1;  %sigma;  % Spatial bandwidth (proportional to the target size)
interp_factor = 0.01;       % Model learning rate (see Eqn 6a, 6b)
cell_size = 4;              % Spatial cell size
global enableGPU;
enableGPU = true;
img_files=images;
show_visualization=0;
video_path='';
% If the provided region is a polygon ...
if numel(region) > 4
    % Init with an axis aligned bounding box with correct area and center
    % coordinate
    cx = mean(region(1:2:end));
    cy = mean(region(2:2:end));
    x1 = min(region(1:2:end));
    x2 = max(region(1:2:end));
    y1 = min(region(2:2:end));
    y2 = max(region(2:2:end));
    A1 = norm(region(1:2) - region(3:4)) * norm(region(3:4) - region(5:6));
    A2 = (x2 - x1) * (y2 - y1);
    s = sqrt(A1/A2);
    w = s * (x2 - x1) + 1;
    h = s * (y2 - y1) + 1;
else
    cx = region(1) + (region(3) - 1)/2;
    cy = region(2) + (region(4) - 1)/2;
    w = region(3);
    h = region(4);
end
pos = round([cy cx]);
target_sz = round([h w]);
      [positions, time] = tracker_ensemble_MLA(video_path, img_files, pos, target_sz, ...
    padding, lambda, output_sigma_factor, interp_factor, cell_size,show_visualization);    
        fps=numel(img_files) / time;  
        for posk=1:length(positions)
             rect_position(posk,:)=floor( [positions(posk,2)-target_sz(2)/2, positions(posk,1)-target_sz(1)/2,target_sz([2,1])]);
        end

        resu.type = 'rect';
        resu.res = rect_position;%each row is a rectangle
        resu.fps = fps; 
        num_frames = numel(images);
results = cell(length(images), 1);
for frame = 1:num_frames
    bb = resu.res(frame,:);
    sz = bb(3:4);
    c = bb(1:2) + (sz - 1)/2;
    new_sz = sz ;
    new_tl = c - (new_sz - 1)/2;
    results{frame} = round([new_tl, new_sz]);
end
    
end

