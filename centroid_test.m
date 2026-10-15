% Repeatability test: run the model with N different noise seeds and check that the
% radar reports the same range/velocity every time.
% Reads three LOGGED signals (they live inside out.logsout, not as out.<name>).
% Run `init` first so lambda, R, target_velocity etc. are in the workspace.

%% Names of the logged signals (change these if yours differ)
name_range = 'range_log';       % km,  strongest cluster (NaN = nothing detected)
name_vel   = 'vel_log';         % m/s, strongest cluster
name_n     = 'n_targets_log';    % number of clusters found

N = 20;
R_est   = nan(N,1);
V_est   = nan(N,1);
n_found = zeros(N,1);

for k = 1:N
    current_seed = randi(100000);                       % new noise realisation each run
    out = sim('Pulse_Radar', 'ReturnWorkspaceOutputs', 'on');

    % On the first run, confirm the names exist before trusting the rest
    if k == 1
        have = out.logsout.getElementNames();
        for nm = {name_range, name_vel, name_n}
            if ~any(strcmp(have, nm{1}))
                error('Logged signal "%s" not found. Logged signals are: %s', ...
                    nm{1}, strjoin(cellstr(have), ', '));
            end
        end
    end

    % Each logged value is one number per frame; the last one is frame 2
    % (frame 1 is the all-zero startup frame).
    v = squeeze(out.logsout.getElement(name_range).Values.Data);   R_est(k)   = v(end);
    v = squeeze(out.logsout.getElement(name_vel).Values.Data);     V_est(k)   = v(end);
    v = squeeze(out.logsout.getElement(name_n).Values.Data);       n_found(k) = v(end);

    fprintf('run %2d/%d done\n', k, N);
end

%% Results
disp(table((1:N)', n_found, R_est, V_est, ...
    'VariableNames', {'run','clusters','range_km','vel_ms'}));

fprintf('\nDetected in %d of %d runs\n', sum(n_found >= 1), N);
fprintf('Runs with more than one cluster: %d\n', sum(n_found > 1));
fprintf('Range: mean %.3f km, std %.3f km\n', mean(R_est,'omitnan'), std(R_est,'omitnan'));
fprintf('Vel:   mean %.2f m/s, std %.3f m/s\n', mean(V_est,'omitnan'), std(V_est,'omitnan'));

%% Pass criteria (Phase 10 exit test)
ok = all(n_found == 1) ...
    && all(abs(R_est - 19.95) < 0.01) ...
    && all(abs(V_est - 5.03) < 0.1);
if ok
    disp('PASS: one cluster, 19.95 km and about 5.0 m/s in every run');
else
    disp('Not all runs met the criteria. Look at the rows above that deviate.');
end