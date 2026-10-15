% Phase 11 Monte Carlo: does the model reliably detect all 3 targets, every run?
% Run `init` first so range, target_velocity, c, Ts, vel_per_bin are in the workspace.

n_trials = 20;

% What we expect, from the current range/target_velocity arrays:
exp_row = round(2*range/c/Ts) + 100;                  % expected peak row of each target
exp_vel = target_velocity;                            % expected velocity of each target

n_found   = zeros(n_trials,1);
row_err   = nan(n_trials, numel(range));
vel_err   = nan(n_trials, numel(range));

for k = 1:n_trials
    current_seed = randi(100000);
    out = sim('Pulse_Radar', 'ReturnWorkspaceOutputs', 'on');

    T = out.logsout.getElement('target_param').Values.Data;
    T = T(:,:,end);                                   % last frame (frame 1 is the all-zero startup)

    n_found(k) = nnz(T(:,1));

    % match each expected target to the nearest reported row, and record the error
    for i = 1:numel(range)
        [~, j] = min(abs(T(1:n_found(k),1) - exp_row(i)));
        if ~isempty(j) && abs(T(j,1) - exp_row(i)) < 10     % only count it as "found" if reasonably close
            row_err(k,i) = T(j,1) - exp_row(i);
            vel_err(k,i) = T(j,8) - exp_vel(i);
        end
    end
end

fprintf('n_targets: %d of %d runs found all 3\n', sum(n_found == numel(range)), n_trials);
fprintf('n_targets histogram:\n'); tabulate(n_found)

for i = 1:numel(range)
    fprintf('\nTarget %d (expected row %d, v = %.1f m/s):\n', i, exp_row(i), exp_vel(i));
    fprintf('  found in %d of %d runs\n', sum(~isnan(row_err(:,i))), n_trials);
    fprintf('  row error:  mean %.2f, std %.2f\n', mean(row_err(:,i),'omitnan'), std(row_err(:,i),'omitnan'));
    fprintf('  vel error:  mean %.3f, std %.3f m/s\n', mean(vel_err(:,i),'omitnan'), std(vel_err(:,i),'omitnan'));
end