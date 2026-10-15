% os_cfar_test: CA-CFAR vs OS-CFAR over N noise seeds (both see the same noise in each run)
N = 20;                 % trials
row_tol = 10;           % rows: a cluster counts as target i if it is this close
vel_wrap = 15;          % m/s, velocity is only defined modulo lambda/(2*PRI)
m_per_row = c*Ts/2;
names = {'CA-CFAR', 'OS-CFAR'};
sig   = {'target_param', 'target_param_os'};

%% Expected targets
active = find(target_rcs > 0);
nA = numel(active);
er = range(active);
exp_row = round(2*er(:)/c/Ts) + 100;
exp_vel = target_velocity(active);  exp_vel = exp_vel(:);
labels = arrayfun(@(i) sprintf('t%d', i), active(:)', 'UniformOutput', false);

%% Run
hit = false(N, nA, 2);   rerr = nan(N, nA, 2);   verr = nan(N, nA, 2);   nfalse = zeros(N, 2);
rng(1);
seeds = randi(100000, N, 1);
for k = 1:N
    current_seed = seeds(k);
    out = sim('Pulse_Radar', 'ReturnWorkspaceOutputs', 'on');
    for m = 1:2
        T = out.logsout.getElement(sig{m}).Values.Data(:, :, end);
        T = T(T(:, 1) > 0, :);
        [hit(k,:,m), rerr(k,:,m), verr(k,:,m), nfalse(k,m)] = ...
            match(T(:,1), T(:,8), exp_row, exp_vel, row_tol, vel_wrap, m_per_row);
    end
    fprintf('run %2d/%d: CA found [%s] +%d false | OS found [%s] +%d false\n', k, N, ...
        strjoin(labels(hit(k,:,1)), ' '), nfalse(k,1), strjoin(labels(hit(k,:,2)), ' '), nfalse(k,2));
end

%% Summary
fprintf('\n--- %d trials, %d active target(s) ---\n', N, nA);
for i = 1:nA
    fprintf('%s (row %d, v = %.2f m/s)\n', labels{i}, exp_row(i), exp_vel(i));
    for m = 1:2
        fprintf('  %s: found %2d/%d | range error %+6.1f +/- %5.1f m | vel error %+6.3f +/- %5.3f m/s\n', ...
            names{m}, sum(hit(:,i,m)), N, mean(rerr(:,i,m), 'omitnan'), std(rerr(:,i,m), 'omitnan'), ...
            mean(verr(:,i,m), 'omitnan'), std(verr(:,i,m), 'omitnan'));
    end
end
fprintf('False clusters in total: CA %d, OS %d\n', sum(nfalse(:,1)), sum(nfalse(:,2)));
fprintf('All targets found together: CA %d/%d, OS %d/%d\n', sum(all(hit(:,:,1),2)), N, sum(all(hit(:,:,2),2)), N);

%% Plot 1: detection rate per target, false clusters per trial
col = [0.00 0.45 0.74; 0.85 0.33 0.10];
rate = 100 * [mean(hit(:,:,1), 1)', mean(hit(:,:,2), 1)'];
figure('Position', [100 100 1000 420]);
tiledlayout(1, 2);
nexttile;
b = bar([rate; nan(1, 2)]);  b(1).FaceColor = col(1,:);  b(2).FaceColor = col(2,:);
xlim([0.5 nA + 0.5]);  ylim([0 105]);  grid on;
set(gca, 'XTick', 1:nA, 'XTickLabel', labels);
ylabel('Detection rate (%)');  title(sprintf('Detection rate per target (%d trials)', N));
legend(names, 'Location', 'southoutside', 'Orientation', 'horizontal');
nexttile;
b = bar(nfalse);  b(1).FaceColor = col(1,:);  b(2).FaceColor = col(2,:);  grid on;
xlabel('Trial');  ylabel('False clusters');  title('Clusters that match no target');

%% Plot 2: accuracy when detected
err = {rerr, verr};
ylab = {'Range error (m)', 'Velocity error (m/s)'};
figure('Position', [120 120 1000 420]);
tiledlayout(1, 2);
for p = 1:2
    nexttile;  hold on;  grid on;
    for i = 1:nA
        for m = 1:2
            e = err{p}(:, i, m);
            x0 = i + (m - 1.5) * 0.3;
            scatter(x0 + 0.08*(rand(N, 1) - 0.5), e, 20, col(m,:), 'filled', 'MarkerFaceAlpha', 0.5);
            errorbar(x0, mean(e, 'omitnan'), std(e, 'omitnan'), 'k', 'LineWidth', 1.5);
        end
    end
    set(gca, 'XTick', 1:nA, 'XTickLabel', labels);
    ylabel(ylab{p});  title([ylab{p} ' when detected']);
    legend([scatter(nan, nan, 20, col(1,:), 'filled'), scatter(nan, nan, 20, col(2,:), 'filled')], names);
end

%% Match clusters to expected targets, one cluster per target, closest first
function [hit, rerr, verr, nfalse] = match(row, vel, exp_row, exp_vel, tol, w, mpr)
nA = numel(exp_row);
hit = false(1, nA);  rerr = nan(1, nA);  verr = nan(1, nA);
D  = abs(row - exp_row.');
dv = mod(vel - exp_vel.' + w/2, w) - w/2;
D(D > tol) = Inf;
used = 0;
while any(isfinite(D(:)))
    [~, j] = min(D(:));
    [ic, it] = ind2sub(size(D), j);
    hit(it) = true;
    rerr(it) = (row(ic) - exp_row(it)) * mpr;
    verr(it) = dv(ic, it);
    D(ic, :) = Inf;  D(:, it) = Inf;
    used = used + 1;
end
nfalse = numel(row) - used;
end