run('init.m');                                  % loads lambda etc. (delete if already in your workspace)

velocities = [5 30 50 70 100 130 150 170 200];
peak_vals = zeros(size(velocities));

for i = 1:length(velocities)
    target_velocity = velocities(i);
    fd = (2 * target_velocity) / lambda;   % recompute, since init.m sets this from target_velocity

    current_seed = 12345;   % FIX the seed so noise and the RCS draw don't confound the comparison
    out = sim('Pulse_Radar', 'ReturnWorkspaceOutputs', 'on');

    mf = squeeze(out.logsout.getElement('mf_magsq').Values.Data(1:1000));  % first pulse, already |y|^2
    peak_vals(i) = max(abs(mf));            % no second square: mf_magsq is already power
end

loss_dB = 10*log10(peak_vals / peak_vals(1));   % loss relative to 5 m/s
fprintf('\n  v (m/s)    peak power      loss (dB)\n');
fprintf('  %6d    %.4e    %7.2f\n', [velocities; peak_vals; loss_dB]);

figure;
plot(velocities, peak_vals, '-o');
xlabel('Target velocity (m/s)');
ylabel('Peak matched-filter power');
title('Peak power vs velocity (fixed seed)');
grid on;

figure;
plot(velocities, loss_dB, '-o');
xlabel('Target velocity (m/s)');
ylabel('Loss relative to 5 m/s (dB)');
title('Doppler mismatch loss (fixed seed)');
grid on;



%Understanding how high velocity affects in Range
N = 100;                          % samples in the pulse
laps = [0.03 0.25 1.0 1.33];      % total turning across the pulse

figure;
for k = 1:4
    ang  = 2*pi*laps(k)*(0:N-1)/N;     % arrow direction at each sample
    z    = exp(1j*ang);                % the arrows (length 1)
    path = [0 cumsum(z)];              % walk tip to tail
    subplot(1,4,k);
    plot(real(path), imag(path), 'b'); hold on;
    plot([0 real(path(end))], [0 imag(path(end))], 'r', 'LineWidth', 2);
    axis equal; grid on;
    title(sprintf('%.2f laps, sum = %.0f', laps(k), abs(path(end))));
end


% Understanding the slow time fft
k = 0:15;
x = exp(1j*2*pi*(5.333/16)*k);     % 16 spinning arrows
X = abs(fft(x));                   % size of each bin's sum
figure;
disp([(0:15)' X'])                 % bin number, sum
bar(0:15, X); xlabel('Bin'); ylabel('Sum (out of 16)');
