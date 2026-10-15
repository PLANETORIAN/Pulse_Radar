% centroid_test.m
% Phase 10: group CFAR detections into clusters and report one range/velocity each.
% Needs a variable `out` from:  out = sim('Pulse_Radar','ReturnWorkspaceOutputs','on');
% and cfar_2d.m (the fixed version) in the same folder.

%% Settings
use_offline_cfar = true;     % true : re-run the fixed cfar_2d on the saved frame (no re-simulation)
                             % false: use the mask the model produced (out.cfar_matrix)
range_offset_row = 100;      % row of zero range: echo delay 0, row 1 = sample 0. The matched-filter
                             % peak is at sample N_delay+99, i.e. row N_delay+100, so subtract 100.
range_per_row    = 150;      % m, c*Ts/2
vel_per_bin      = 0.9375;   % m/s, lambda/(2*N_cpi*PRI)

%% Load one frame (frame 1 is the all-zero startup frame)
rd = out.logsout.getElement('rd_matrix').Values.Data(:,:,2);

if use_offline_cfar
    det = cfar_2d(rd);
else
    det = out.cfar_matrix(:,:,end);
end

%% Cluster the detections
cc = bwconncomp(det, 8);                       % needs Image Processing Toolbox
fprintf('%d cluster(s) found\n', cc.NumObjects);

for i = 1:cc.NumObjects
    idx    = cc.PixelIdxList{i};
    [r, d] = ind2sub(size(det), idx);
    p      = rd(idx);                          % weights = linear power, not the 0/1 mask

    [~, k] = max(p);
    peak   = [r(k), d(k)];
    cent   = [sum(r.*p)/sum(p), sum(d.*p)/sum(p)];

    % Range from the PEAK (150 m bins already resolve it); velocity from the CENTROID
    % (0.94 m/s bins are coarse, and the target sits between two bins).
    range_m = (peak(1) - range_offset_row) * range_per_row;
    vel_ms  = (cent(2) - 1) * vel_per_bin;

    fprintf('\nCluster %d: %d cells, rows %d..%d, cols %d..%d\n', ...
            i, numel(idx), min(r), max(r), min(d), max(d));
    fprintf('  peak (%d,%d)   centroid (%.1f,%.2f)\n', peak(1), peak(2), cent(1), cent(2));
    fprintf('  reported: R = %.2f km (from peak), v = %.2f m/s (from centroid)\n', ...
            range_m/1000, vel_ms);
    fprintf('  for comparison, range from the centroid = %.2f km\n', ...
            (cent(1) - range_offset_row)*range_per_row/1000);

    % Mask symmetry about the peak: a big imbalance means the mask is cut off on one side
    fprintf('  mask extent: %d rows below the peak, %d rows above\n', ...
            peak(1) - min(r), max(r) - peak(1));

    % Per-column breakdown
    for c = unique(d)'
        m  = (d == c);
        rr = r(m);  pp = rd(idx(m));
        [~, kk] = max(pp);
        fprintf('  col %d: rows %d..%d, power-centroid %.1f, peak row %d\n', ...
                c, min(rr), max(rr), sum(rr.*pp)/sum(pp), rr(kk));
    end

    % Centroid of the raw power in the peak column, ignoring CFAR entirely.
    % This should equal the peak row if the response is symmetric.
    rows = max(1, peak(1)-120) : min(size(rd,1), peak(1)+120);
    pc   = rd(rows, peak(2));
    fprintf('  unmasked centroid in column %d: %.1f\n', peak(2), sum(rows(:).*pc)/sum(pc));
end

%% Compare with the truth, if the workspace has it
if exist('R','var'),               fprintf('\ntrue R = %.2f km\n', R/1000);                   end
if exist('target_velocity','var'), fprintf('true v = %.1f m/s, aliased = %.2f m/s\n', ...
        target_velocity, mod(target_velocity + 7.5, 15) - 7.5);                               end


function detections = cfar_2d(rd_matrix)
% 2D cell-averaging CFAR on a range-Doppler power map.
% rd_matrix : 1000x16 LINEAR power (|u|^2), not dB
% detections: 1000x16 binary map
%
% Changes from the previous version:
%   1. Gr 200 -> 100 (half the 199-sample matched-filter triangle).
%   2. The matrix is padded, so EVERY range row is tested. Before, rows within
%      Tr+Gr of either end were skipped, which made close targets undetectable.
%   3. The Doppler axis is padded circularly (velocity wraps around).
% The same code runs in the Simulink MATLAB Function block and from a script.

[num_ranges, num_dopplers] = size(rd_matrix);

Pfa = 1e-6;
Tr = 16;    Td = 1;     % training cells (range, Doppler), per side
Gr = 100;   Gd = 1;     % guard cells    (range, Doppler), per side

N_train = (2*(Tr+Gr)+1)*(2*(Td+Gd)+1) - (2*Gr+1)*(2*Gd+1);
alpha   = N_train * (Pfa^(-1/N_train) - 1);

pr = Tr + Gr;           % half-height of the window
pd = Td + Gd;           % half-width  of the window

% Pad with a noise-level value. For exponential noise power, median = mean*ln2,
% so median/ln2 estimates the mean and is not pulled up by the target.
% Zeros would make the edge estimate too low and cause false alarms there.
noise_level = median(rd_matrix(:)) / log(2);
rd_pad = noise_level * ones(num_ranges + 2*pr, num_dopplers + 2*pd);
rd_pad(pr+1:pr+num_ranges, pd+1:pd+num_dopplers) = rd_matrix;
rd_pad(pr+1:pr+num_ranges, 1:pd) = rd_matrix(:, num_dopplers-pd+1:num_dopplers);
rd_pad(pr+1:pr+num_ranges, pd+num_dopplers+1:end) = rd_matrix(:, 1:pd);

detections = zeros(num_ranges, num_dopplers);

for r = 1:num_ranges
    for d = 1:num_dopplers
        rc = r + pr;                                   % cell position in padded matrix
        dc = d + pd;

        window = rd_pad(rc-pr : rc+pr, dc-pd : dc+pd); % outer window
        guard  = rd_pad(rc-Gr : rc+Gr, dc-Gd : dc+Gd); % guard region + CUT

        noise_avg = (sum(window(:)) - sum(guard(:))) / N_train;

        if rd_pad(rc, dc) > alpha * noise_avg
            detections(r, d) = 1;
        end
    end
end
end