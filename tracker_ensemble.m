% tracker_ensemble: Correlation filter tracking with convolutional features
%
% Input:
%   - video_path:          path to the image sequence
%   - img_files:           list of image names
%   - pos:                 intialized center position of the target in (row, col)
%   - target_sz:           intialized target size in (Height, Width)
% 	- padding:             padding parameter for the search area
%   - lambda:              regularization term for ridge regression
%   - output_sigma_factor: spatial bandwidth for the Gaussian label
%   - interp_factor:       learning rate for model update
%   - cell_size:           spatial quantization level
%   - show_visualization:  set to True for showing intermediate results
% Output:
%   - positions:           predicted target position at each frame
%   - time:                time spent for tracking
%
%  cite:
%   "Hierarchical Convolutional Features for Visual Tracking
%   Chao Ma, Jia-Bin Huang, Xiaokang Yang, and Ming-Hsuan Yang
%   IEEE International Conference on Computer Vision, ICCV 2015"
%
function [positions, time] = tracker_ensemble(video_path, img_files, pos, target_sz, ...
    padding, lambda, output_sigma_factor, interp_factor, cell_size, show_visualization,st,md)


% ===============================================================================
% Environment setting
% ================================================================================
%%
params = readParams('params.txt');
im = imread(fullfile(video_path, img_files{1}));
    % is a grayscale sequence ?
resize_image = (sqrt(prod(target_sz)) >= 100);  %diagonal size >= threshold
if resize_image,
		pos = floor(pos / 2);
		target_sz = floor(target_sz / 2);
        im = imresize(im, 0.5);
end
if(size(im,3)==1)
  params.grayscale_sequence = true;
end
im_sz=size(im);
if(size(im,3)==1)
  params.grayscale_sequence = true;
end
params.img_files = img_files;
params.img_path = video_path;
params.init_pos = pos;
params.target_sz = target_sz;
[p, bg_area, fg_area, area_resize_factor] = initializeAllAreas(im, params);
   %% SCALE ADAPTATION INITIALIZATION
    if p.scale_adaptation
        % Code from DSST
        scale_factor = 1;
        base_target_sz = target_sz;
        scale_sigma = sqrt(p.num_scales) * p.scale_sigma_factor;
        ss = (1:p.num_scales) - ceil(p.num_scales/2);
        ys = exp(-0.5 * (ss.^2) / scale_sigma^2);
        ysf = single(fft(ys));
        if mod(p.num_scales,2) == 0
            scale_window = single(hann(p.num_scales+1));
            scale_window = scale_window(2:end);
        else
            scale_window = single(hann(p.num_scales));
        end;

        ss = 1:p.num_scales;
        scale_factors = p.scale_step.^(ceil(p.num_scales/2) - ss);

        if p.scale_model_factor^2 * prod(p.norm_target_sz) > p.scale_model_max_area
            p.scale_model_factor = sqrt(p.scale_model_max_area/prod(p.norm_target_sz));
        end

        scale_model_sz = floor(p.norm_target_sz * p.scale_model_factor);
        % find maximum and minimum scales
        min_scale_factor = p.scale_step ^ ceil(log(max(5 ./ bg_area)) / log(p.scale_step));
        max_scale_factor = p.scale_step ^ floor(log(min([size(im,1) size(im,2)] ./ target_sz)) / log(p.scale_step));
    end

kernel.type='linear'; %gaussian  polynomial  linear
kernel.sigma=0.5;
indLayers =[29,35];%, 28, 19];   35;% The CNN layers Conv5-4, Conv4-4, and Conv3-4 in VGG Net
nweights  = [1];%, 0.5, 0.02]; % Weights for combining correlation filter responses
numLayers = length(indLayers);

% Get image size and search window size
% im_sz     = size(imread([video_path img_files{1}]));

window_sz =get_search_window(target_sz, im_sz, padding);
% cell_size = min(cell_size, max(1, ceil(sqrt(prod(window_sz)/(1510)))));
% Compute the sigma for the Gaussian function label
output_sigma = sqrt(prod(target_sz)) * output_sigma_factor / cell_size;

%create regression labels, gaussian shaped, with a bandwidth
%proportional to target size    d=bsxfun(@times,c,[1 2]);

l1_patch_num = floor(window_sz/ cell_size);



% Pre-compute the Fourier Transform of the Gaussian function label
yf = fft2(gaussian_shaped_labels(output_sigma*1.5, l1_patch_num));  %1.5
% yf06 = fft2(gaussian_shaped_labels(output_sigma, l1_patch_num));
 % yf25 = fft2(gaussian_shaped_labels(output_sigma*2.5, l1_patch_num));
% yf20 = fft2(gaussian_shaped_labels(output_sigma*2, l1_patch_num));
% yf30 = fft2(gaussian_shaped_labels(output_sigma*2.5, l1_patch_num));
% Pre-compute and cache the cosine window (for avoiding boundary discontinuity)
cos_window = hann(size(yf,1)) * hann(size(yf,2))';

% Create video interface for visualization
if(show_visualization)
    update_visualization = show_video(img_files, video_path);
end

% Initialize variables for calculating FPS and distance precision
time      = 0;
positions = zeros(numel(img_files), 4);
nweights  = reshape(nweights,1,1,[]);
respo(1)=1;
apecs(1)=1;
%%%find the best response layers
%  indLayers = 10:37;   % The CNN layers Conv5-4, Conv4-4, and Conv3-4 in VGG Net  [37, 28]
%  nweights=[1 1 1 1];%  =[1,1,1,1,1,1]; % Weights for combining correlation filter responses
% numLayers = length(indLayers);
% % 
% 
%  im = imread([video_path img_files{1}]); % Load the image at the current frame
%     if ismatrix(im)
%         im = cat(3, im, im, im);
%     end
% feat = extractFeature(im, pos, window_sz, cos_window, indLayers);
% [mxf,malphaf] = GetLM(feat, yf, interp_factor, lambda);
% ar=rand(1,5)/5;
% ah=rand(1,5)/5;
% for ti=1:5
%  v1(ti)=floor(1 + min(target_sz)*ar(ti));
%  h1(ti)=floor(1 + min(target_sz)*ah(ti));
% end
% for vi=1:5
%     for hi=1:5
%         im1=circshift(im,[v1(vi),h1(hi)]);
%         feat = extractFeature(im1, pos, window_sz, cos_window, indLayers);
%         [mt,pt] = GetLayerIndex(feat, indLayers,mxf, malphaf,cell_size);
%          for mi=1:numel(feat)
%             dis(mi)=sqrt(sum((pt(mi,:)-[v1(vi),h1(hi)]).^2));
%         end
%        mts((vi-1)*1+hi,:)=mt;
%     end
% end
% mts=sum(mts,1);
%  [tmp,idx]=sort(mts,'descend');
% ly=indLayers(idx)
% im = imread([video_path img_files{1}]); % Load the image at the current frame
%  if resize_image,
% 	  im = imresize(im, 0.5);
%  end
if ismatrix(im)
        im = cat(3, im, im, im);
end
midx{1}=1:512;%28
midx{2}=1:512;%29
midx{3}=1:512;%31
midx{4}=1:512;%33
midx{5}=1:512;%35
midx{6}=1:512;%37


feat = extractFeature(im, pos, window_sz, cos_window, indLayers,midx,scale_factor);

for ii=1:numLayers
        sm=floor(size(feat{1})/2);
        celt=floor(target_sz/8);
        for fi=1:sm(3)*2
            mfm(fi)=mean2(feat{ii}(sm(1)-celt(1):sm(1)+celt(1),sm(2)-celt(2):sm(2)+celt(2),fi))/(1+mean2(feat{ii}(:,:,fi)));
        end
%         mx{ii}=max(mfm); 
%         mi{ii}=min(mfm);        
        mxm{ii}=mean(mfm);        
 end

for ii=1:numLayers
        sm=floor(size(feat{1})/2);
        celt=floor(target_sz/8);
        midx{ii}=[];

   %   midx=di(1:64);
     for fi=1:sm(3)*2
            if mean2(feat{ii}(sm(1)-celt(1):sm(1)+celt(1),sm(2)-celt(2):sm(2)+celt(2),fi))/(1+mean2(feat{ii}(:,:,fi)))>st%;mxm{ii}*2/3 1.2
                midx{ii}=[fi,midx{ii}];
            end
     end
     smix(ii)=length(midx{ii});

 end
%    lyi=find(smix==max(smix));
%    if length(lyi)>1
%        lyi=lyi(1);
%    end
% indL=indLayers(lyi);
% indLayers =indL;%, 28, 19];   % The CNN layers Conv5-4, Conv4-4, and Conv3-4 in VGG Net
% nweights  = [1];%, 0.5, 0.02]; % Weights for combining correlation filter responses
% numLayers = length(indLayers);
% tt=midx{lyi};
% midx{1}=tt;
% Note: variables ending with 'f' are in the Fourier domain.
model_xf     = cell(1, numLayers);
model_alphaf = cell(1, numLayers);
% model_alphaf06 = cell(1, numLayers);
% model_alphaf20 = cell(1, numLayers);
% model_alphaf25 = cell(1, numLayers);
% model_alphaf30 = cell(1, numLayers);
% ================================================================================
% Start tracking
% ================================================================================
pr=6;
i=1;
t=0;
for frame = 1:numel(img_files),
    im = imread([video_path img_files{frame}]); % Load the image at the current frame
     if resize_image,
        im = imresize(im, 0.5);
    end
    if ismatrix(im)
        im = cat(3, im, im, im);
    end
    
    tic();
    % ================================================================================
    % Predicting the object position from the learned object model
    % ================================================================================
    if frame > 1
        % Extracting hierarchical convolutional features
        feat = extractFeature(im, pos, window_sz, cos_window, indLayers,midx,scale_factor);
        % Predict position
        [pos,pr,respo(frame),apecs(frame)]  = predictPosition(feat, pos,indLayers, nweights, cell_size, l1_patch_num, ...
            model_xf, model_alphaf,kernel,i);
    
    %% SCALE SPACE SEARCH
            if p.scale_adaptation
                im_patch_scale = getScaleSubwindow(im, pos, base_target_sz, scale_factor * scale_factors, scale_window, scale_model_sz, p.hog_scale_cell_size);
                xsf = fft(im_patch_scale,[],2);
                scale_response = real(ifft(sum(sf_num .* xsf, 1) ./ (sf_den + p.lambda) ));
                recovered_scale = ind2sub(size(scale_response),find(scale_response == max(scale_response(:)), 1));
                %set the scale
                scale_factor = scale_factor * scale_factors(recovered_scale);

                if scale_factor < min_scale_factor
                    scale_factor = min_scale_factor;
                elseif scale_factor > max_scale_factor
                    scale_factor = max_scale_factor;
                end
                % use new scale to update bboxes for target, filter, bg and fg models
                target_sz = round(base_target_sz * scale_factor);
                avg_dim = sum(target_sz)/2;
                bg_area = round(target_sz + avg_dim);
                if(bg_area(2)>size(im,2)),  bg_area(2)=size(im,2)-1;    end
                if(bg_area(1)>size(im,1)),  bg_area(1)=size(im,1)-1;    end

                bg_area = bg_area - mod(bg_area - target_sz, 2);
                fg_area = round(target_sz - avg_dim * p.inner_padding);
                fg_area = fg_area + mod(bg_area - fg_area, 2);
                % Compute the rectangle with (or close to) params.fixed_area and
                % same aspect ratio as the target bboxgetScaleSubwindow
                area_resize_factor = sqrt(p.fixed_area/prod(bg_area));
            end     
    end
    % ================================================================================
    % Learning correlation filters over hierarchical convolutional features
    % ================================================================================
    % Extracting hierarchical convolutional featuresmod(frame,md)==0&&(frame>=2 &&respo(frame)>mean(respo(2:frame))*0.4&&apecs(frame)>mean(apecs(2:frame))*0.6))
       if (frame==1) ||mod(frame,md)==0    %2
     feat  = extractFeature(im, pos, window_sz, cos_window, indLayers,midx,scale_factor);
    % Model update
    [model_xf, model_alphaf] = updateModel(feat, yf,interp_factor, lambda, frame, ...
        model_xf, model_alphaf,kernel);
       end
      if pr<4.13   %4.6&&i==1
           t=t+1;
            i=-i;
      end
       if t>50
           i=1;
       end
      
         if p.scale_adaptation
            im_patch_scale = getScaleSubwindow(im, pos, base_target_sz, scale_factor*scale_factors, scale_window, scale_model_sz, p.hog_scale_cell_size);
            xsf = fft(im_patch_scale,[],2);
            new_sf_num = bsxfun(@times, ysf, conj(xsf));
            new_sf_den = sum(xsf .* conj(xsf), 1);
            if frame == 1,
                sf_den = new_sf_den;
                sf_num = new_sf_num;
            else
                sf_den = (1 - p.learning_rate_scale) * sf_den + p.learning_rate_scale * new_sf_den;
                sf_num = (1 - p.learning_rate_scale) * sf_num + p.learning_rate_scale * new_sf_num;
            end
        end
    % ================================================================================
    % Save predicted position and timing
    % ================================================================================
    positions(frame,:) = [pos,target_sz];
    if resize_image,
         positions(frame,:) = [pos,target_sz]*2;         
    end
    time = time + toc();
    % Visualization
    if show_visualization,
        box = [pos([2,1]) - target_sz([2,1])/2, target_sz([2,1])];
        if resize_image,          
        box = [pos([2,1]) - target_sz([2,1])/2, target_sz([2,1])]*2;
        end
%         box1 = [pos06([2,1]) - target_sz([2,1])/2, target_sz([2,1])];
%         box2 = [pos20([2,1]) - target_sz([2,1])/2, target_sz([2,1])];
%         box3 = [pos30([2,1]) - target_sz([2,1])/2, target_sz([2,1])];
        stop = update_visualization(frame, box);
        if stop, break, end  %user pressed Esc, stop early
        drawnow
        % 			pause(0.05)  % uncomment to run slower

    end
end
end


function [pos,pr,mres,apec]= predictPosition(feat, pos, indLayers, nweights, cell_size, l1_patch_num, ...
    model_xf, model_alphaf,kernel,ti)

% ================================================================================
% Compute correlation filter responses at each layer
% ================================================================================
% indLayers=11;

res_layer = zeros([l1_patch_num, length(indLayers)]);
if ti==1
    ii=1;
else
    ii=2;
end
% for ii = 1 : 1
    zf = fft2(feat{ii});
    switch kernel.type
        case 'gaussian',
                   kzf = gaussian_correlation(zf, model_xf{ii}, kernel.sigma);
        case 'polynomial',
                   kzf = polynomial_correlation(zf, model_xf{ii}, kernel.poly_a, kernel.poly_b);
         case 'linear',
                   kzf=sum(zf .* conj(model_xf{ii}), 3) / numel(zf);
    end
    res_layer(:,:,ii) = real(fftshift(ifft2(model_alphaf{ii} .* kzf)));  %equation for fast detection
response =sum(bsxfun(@times, res_layer, nweights), 3);

% response=response+0.6*res_layer06+0.5*res_layer20+0.4*res_layer30;
% ================================================================================
% Find target location
% ================================================================================
% Target location is at the maximum response. we must take into
% account the fact that, if the target doesn't move, the peak
% will appear at the top-left corner, not at the center (this is
% discussed in the KCF paper). The responses wrap around cyclically.
mres=max(response(:));
minres=min(response(:));
apec=(mres-minres)^2/mean2((response-minres).^2);
u=mean2(response);
f=std2(response);
pr=(mres-u)/f;  
    if pr<9
        up=0.1*pr;  % upcnn=0.8;
    else
        up=0;   %upcnn=0.1*pr;
    end 
[vert_delta, horiz_delta] = find(response ==mres, 1);
vert_delta  = vert_delta  - floor(size(zf,1)/2);
horiz_delta = horiz_delta - floor(size(zf,2)/2);
% 
% %Map the position to the image space
 pos= pos + cell_size * [vert_delta - 1, horiz_delta - 1];

end

function [model_xf, model_alphaf] = updateModel(feat, yf,interp_factor, lambda, frame, ...
    model_xf, model_alphaf,kernel)

numLayers = length(feat);

% ================================================================================
% Initialization
% ================================================================================
xf       = cell(1, numLayers);
alphaf   = cell(1, numLayers);

% ================================================================================
% Model update
% ================================================================================
for ii=1 : 2
    xf{ii} = fft2(feat{ii});
    switch kernel.type
        case 'gaussian',
			kf = gaussian_correlation(xf{ii}, xf{ii}, kernel.sigma);
		case 'polynomial',
			kf = polynomial_correlation(xf{ii}, xf{ii}, kernel.poly_a, kernel.poly_b);
		case 'linear',
			kf = sum(xf{ii} .* conj(xf{ii}), 3) / numel(xf{ii});
    end
    alphaf{ii} = yf./ (kf+ lambda);   % Fast training
end

% Model initialization or update
if frame == 1,  % First frame, train with a single image
    for ii=1:2
        model_alphaf{ii} = alphaf{ii};
        model_xf{ii} = xf{ii};
    end
else
    % Online model update using learning rate interp_factor
    for ii=1:2
        model_alphaf{ii} = (1 - interp_factor) * model_alphaf{ii} + interp_factor * alphaf{ii};
        model_xf{ii}     = (1 - interp_factor) * model_xf{ii}     + interp_factor * xf{ii};
    end
end
end

function feat  = extractFeature(im, pos, window_sz, cos_window, indLayers,midx,s_factor)
if s_factor<0.7
    s_factor=0.7;  
% elseif s_factor>1.5
%     s_factor=1.5;
end
% Get the search window from previous detection
patch = get_subwindow(im, pos, floor(window_sz*s_factor));
%resize to orginal size
% Extracting hierarchical convolutional features
feat  = get_features_MLA(patch, cos_window, indLayers,midx);

end
