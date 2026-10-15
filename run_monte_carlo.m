% --- Phase 8.5: Swerling I Monte Carlo Validation ---
num_trials = 100;       
successful_hits = 0;    

disp('Starting Monte Carlo Simulation... (This may take a minute)');

% Load the static physics (radar_const) once
run('init.m'); 

for trial = 1:num_trials

    % 1. Inject a brand new random seed into the MATLAB workspace
    % Simulink will pull this variable into the Uniform Random Number block
    current_seed = randi(100000); 

    % 2. Command Simulink to run silently
    out = sim('Pulse_Radar', 'ReturnWorkspaceOutputs', 'on');

    % 3. Extract the final 1000x16 binary matrix from the run
    detection_map = out.cfar_matrix(:, :, end);

    % 4. Check the known target coordinate [Y = 232, X = 6]
    target_pixel = detection_map(232, 6);

    % 5. Log the result
    if target_pixel == 1
        successful_hits = successful_hits + 1;
    end

    % Print progress
    if mod(trial, 10) == 0
        fprintf('Completed %d / %d trials...\n', trial, num_trials);
    end
end

% --- Calculate and Display Final Statistics ---
Pd = successful_hits / num_trials;
fprintf('\n--- VALIDATION RESULTS ---\n');
fprintf('Probability of Detection (Pd): %.2f%%\n', Pd * 100);