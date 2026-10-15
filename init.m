% init.m  --  parameters for Pulse_Radar.slx (multi-target)

c      = 3e8;
PRI    = 1e-3;
tau_p  = 0.1e-3;

% --- Targets: one entry per target, all three arrays must have the same length ---
range = [20e3 40e3 70e3];   
target_velocity = [2 3 5];  
target_rcs = [1 1 1];                  % m^2, set an entry to 0 to switch that target off
assert(numel(range) == numel(target_velocity) && numel(range) == numel(target_rcs), ...
    'range, target_velocity and target_rcs must have the same length.');
range(range < 1) = 1;                       % 1 m floor: radar_const ~ 1/range^4 must stay finite in single precision
tau   = (2 * range) / c;                    % round-trip delay of each target (s)
Ts    = 1e-6;                               % 1 microsecond sample time (150 m range bins)
R_min = (c*tau_p)/2;                        % blind range = range resolution (15 km)

% --- Discrete DSP Parameters for Simulink ---
N_PRI   = round(PRI / Ts);                  % Period in samples (1000)
N_tau_p = round(tau_p / Ts);                % Pulse width in samples (100)
N_delay = round(tau / Ts);                  % Round-trip delay of each target in samples
noise_variance = 0.64;                      % legacy value from an earlier version; remove once no block uses it

% --- RF & Physical Parameters ---
fc     = 10e9;                              % Carrier frequency (10 GHz)
lambda = c / fc;                            % Wavelength (3 cm)
Pt     = 100e3;                             % Peak transmit power (100 kW)
G_dB   = 35;                                % Antenna gain (dB)
G      = 10^(G_dB / 10);                    % Antenna gain (linear)

%% --- Channel transfer function H[k], frequency domain, delay + amplitude only ---
N = N_PRI;
k_idx = (0:N-1)';

H_delay = exp(-1j*2*pi*k_idx*N_delay/N);     % 1000xN_targets, phase ramp per target - this is H_fixed now

% --- Random seed ---
% Default seed so Simulink can run manually from the GUI.
% Echo uses current_seed + 100*(1:numel(range)); the noise blocks use current_seed + 1, + 2, ...
current_seed = randi(100000);

Loss_dB = 2;                                % System losses (dB)
L = 10^(Loss_dB / 10);                      % System losses (linear)

% --- Target amplitude (radar range equation), one value per target ---
% Pr = (Pt * G^2 * lambda^2 * sigma) / ((4*pi)^3 * R^4 * L)
% radar_const is Pr for sigma = 1 m^2; the Echo gain is  -target_rcs.*radar_const
radar_const = (Pt * G^2 * lambda^2) ./ (((4*pi)^3) * (range.^4) * L);
assert(all(isfinite(single(-target_rcs .* radar_const))), ...
    'Echo gain is not finite in single precision. Check range (too small?) and target_rcs.');
Pr   = target_rcs .* radar_const;           % received power of each target (W)
V_rx = sqrt(Pr);                            % baseband voltage amplitude

% --- Receiver Thermal Noise ---
k_B = 1.38e-23;                             % Boltzmann constant (J/K)
T0  = 290;                                  % Standard temperature (K)
B   = 1 / Ts;                               % Receiver bandwidth (1 MHz)
NF_dB = 3;                                  % Noise Figure (dB)
F   = 10^(NF_dB / 10);                      % Noise Figure (linear)
Pn  = k_B * T0 * B * F;                     % Noise power (W)
noise_variance_IQ = Pn / 2;                 % per I/Q channel

% --- CA-CFAR Parameters (1D) ---
Pfa     = 1e-6;                             % Desired probability of false alarm
N_train = 32;                               % Training cells (16 leading, 16 lagging)
N_guard = 200;                              % Guard cells (100 per side, covers the 199-sample triangle)

% 1. Threshold multiplier (alpha) for square-law detection
alpha = N_train * (Pfa^(-1/N_train) - 1);

% 2. HDL-portable sliding window (FIR taps), averaged by N_train
cfar_window = [ones(1, N_train/2), zeros(1, N_guard + 1), ones(1, N_train/2)] / N_train;

% 3. Delay that aligns the CUT with its threshold
cfar_delay = (N_train/2) + (N_guard/2);

% --- Target Doppler (one value per target) ---
fd = (2 * target_velocity) / lambda;        % Doppler frequency shift of each target (Hz)

% --- Coherent Processing Interval (CPI) ---
N_cpi  = 16;                                % Pulses per CPI (FFT size for Doppler)
T_stop = N_cpi * PRI;                       % Simulate exactly 1 CPI

% --- MTI Canceller Parameters ---
% 2-pulse canceller: H(z) = 1 - z^(-N_PRI)
MTI_delay = N_PRI;                          % Delay one full PRI (1000 samples)

% --- Range Calculation Parameters ---
range_per_sample = (c * Ts) / 2;            % Physical distance per sample bin (150 m)

% --- Hardware Calibration (Pipeline Latency) ---
matched_filter_delay = N_tau_p - 1;         % Peak occurs at N-1 in discrete convolution (99)
drop_threshold_delay = 8;

% Echo chain latency. Echo is now Buffer(N_PRI) -> FFT -> x H -> IFFT -> x A -> Unbuffer.
% The Buffer must collect a whole PRI before it releases anything, so every echo comes out
% exactly one PRI (N_PRI samples) later than N_delay. Measured on the Pure Echo scope: echoes
% that should start at 0.30 ms and 0.47 ms (300 and 467 samples) start at about 1.3 ms and 1.47 ms.
% Because of this, the echo of pulse k lands in PRI k+1, so the first PRI has no echo.
echo_chain_delay = N_PRI;                   % 1000 samples = 1 PRI

% Latency of the 1D detection chain, counted from the start of the PRI the echo arrives in.
% echo_chain_delay is exactly one PRI, so it drops out of any index that restarts every PRI.
hardware_delay_samples = matched_filter_delay + cfar_delay + drop_threshold_delay;   % 223

% Same latency counted from the start of the simulation (a counter that never resets).
% Use this one in the Range block instead if that block's index is not reset every PRI.
hardware_delay_total = hardware_delay_samples + echo_chain_delay;                    % 1223

% --- Maximum unambiguous velocity and Doppler bin width ---
V_max       = lambda/(4*Ts*N_PRI);          % 7.5 m/s
vel_per_bin = lambda/(2*N_cpi*PRI);         % 0.9375 m/s

% --- DSP Windowing Functions ---
doppler_window = hamming(N_cpi)';           % 1x16 curve to crush FFT leakage
range_window   = hamming(N_tau_p)';         % 1x100 curve (not used by the matched filter at the moment)

% --- Where each active target should appear on the range-Doppler map (for checking) ---
% The extra PRI of echo latency does not move these: a delay of exactly one PRI leaves the
% position inside the PRI unchanged.
for k = find(target_rcs > 0)
    row = mod(mod(N_delay(k), N_PRI) + 100 - 1, N_PRI) + 1;     % ranges past 150 km fold back
    col = mod(target_velocity(k)/vel_per_bin, N_cpi) + 1;       % velocities past +-7.5 m/s alias
    fprintf('Target %d: range %.1f km, v = %.1f m/s -> expected peak row %d, Doppler column %.2f\n', ...
            k, range(k)/1e3, target_velocity(k), row, col);
end