%% ========================================================================
%  PHASE 2: NTN Channel Modeling
%  ========================================================================
%  Performance Analysis of 5G NR in LEO Non-Terrestrial Networks
%
%  This phase configures 3GPP-compliant NTN channel models.
%  CRITICAL: Channel profiles map to ENVIRONMENT, NOT payload type.
%  Both transparent and regenerative payloads use the SAME channel.
%
%  Models implemented:
%    1. NTN-TDL wideband fading (nrTDLChannel) — 4 environments
%    2. P.681 LMS narrowband shadowing (p681LMSChannel) — 3 environments
%    3. Doppler computation (orbital + UE mobility)
%
%  Outputs saved to results/:
%    phase2_results.mat  — Channel objects and Doppler data for Phase 3+
%    6 publication-quality figures
%
%  3GPP References:
%    TR 38.811 Sec 6.9.2   — NTN TDL delay profiles
%    TR 38.811 Table 6.9.2-1 — Delay spread per environment
%    TR 38.821 Sec 6.1.4   — Doppler characterization
%    ITU-R P.681            — LMS channel model
%  ========================================================================
clc; clear; close all;

%% Add paths and load Phase 1 results
addpath('config');
addpath('helpers');
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 2: NTN Channel Modeling\n');
fprintf('  LEO NTN — 5G NR Performance Analysis\n');
fprintf('============================================================\n\n');

% Load Phase 1 data
fprintf('--- Loading Phase 1 results ---\n');
p1File = fullfile(params.outputDir, 'phase1_results.mat');
if ~exist(p1File, 'file')
    error('Phase 1 results not found. Run phase1_scenario.m first.');
end
load(p1File, 'phase1');
fprintf('  Loaded: %s\n\n', p1File);

%% =====================================================================
%  SECTION 1: DOPPLER SHIFT ANALYSIS
%  =====================================================================
%  Two independent Doppler components in NTN:
%    1. Satellite orbital Doppler: ~24-48 kHz at S-band (deterministic)
%    2. UE mobility Doppler: ~5.6 Hz at pedestrian speed (stochastic fading)
%  These are handled SEPARATELY by the 5G Toolbox nrTDLChannel.
%  =====================================================================
fprintf('--- Section 1: Doppler Shift Analysis ---\n');

c  = params.c;
fc = params.rf.carrierFrequency;

% --- Satellite Orbital Doppler ---
% Computed analytically using dopplerShiftCircularOrbit()
% This is elevation-dependent: maximum at low elevation, zero at zenith
elevSweep = 10:5:90;
satDoppler = zeros(size(elevSweep));

for k = 1:length(elevSweep)
    satDoppler(k) = dopplerShiftCircularOrbit( ...
        elevSweep(k), ...
        params.sat.altitude, ...
        0, ...                    % Mobile altitude = 0
        fc);
end

fprintf('  Satellite orbital Doppler (via dopplerShiftCircularOrbit):\n');
fprintf('    At 10 deg elevation: %.1f kHz\n', satDoppler(1)/1e3);
fprintf('    At 50 deg elevation: %.1f kHz\n', satDoppler(9)/1e3);
fprintf('    At 90 deg elevation: %.1f kHz (zenith)\n', satDoppler(end)/1e3);

% --- UE Mobility Doppler ---
% fd = v * fc / c (classical Doppler from ground user motion)
mobileDoppler = params.ue.speed_ms * fc / c;
fprintf('    UE mobility Doppler (%.0f km/h): %.1f Hz\n\n', ...
    params.ue.speed_kmh, mobileDoppler);

% Reference elevation for channel configuration (typical operating point)
refElev = 50;  % degrees
refSatDoppler = dopplerShiftCircularOrbit(refElev, params.sat.altitude, 0, fc);
fprintf('  Reference operating point (elevation = %d deg):\n', refElev);
fprintf('    Satellite Doppler : %.1f kHz\n', refSatDoppler/1e3);
fprintf('    UE Doppler        : %.1f Hz\n', mobileDoppler);
fprintf('    Total max Doppler : %.1f kHz\n\n', (refSatDoppler + mobileDoppler)/1e3);

%% =====================================================================
%  SECTION 2: NTN-TDL WIDEBAND CHANNEL CONFIGURATION
%  =====================================================================
%  3GPP TR 38.811 defines four NTN TDL profiles based on ENVIRONMENT:
%    NTN-TDL-A: Dense urban / deep indoor (NLoS, Rayleigh)
%    NTN-TDL-B: Urban moderate (weak LoS)
%    NTN-TDL-C: Suburban / light urban (LoS dominant)
%    NTN-TDL-D: Rural / open areas (strong LoS)
%
%  BOTH payload types use the SAME profile for a given environment.
%  =====================================================================
fprintf('--- Section 2: NTN-TDL Wideband Channel Configuration ---\n');

% Define environment configurations
envConfigs = struct();

envConfigs(1).name         = 'Dense Urban';
envConfigs(1).profile      = 'NTN-TDL-A';
envConfigs(1).delaySpread  = params.channel.delaySpread.denseUrban;
envConfigs(1).description  = 'NLoS, Rayleigh fading, high delay spread';

envConfigs(2).name         = 'Urban';
envConfigs(2).profile      = 'NTN-TDL-B';
envConfigs(2).delaySpread  = params.channel.delaySpread.urban;
envConfigs(2).description  = 'Weak LoS, moderate fading';

envConfigs(3).name         = 'Suburban';
envConfigs(3).profile      = 'NTN-TDL-C';
envConfigs(3).delaySpread  = params.channel.delaySpread.suburban;
envConfigs(3).description  = 'LoS dominant, medium Rician K-factor';

envConfigs(4).name         = 'Rural';
envConfigs(4).profile      = 'NTN-TDL-D';
envConfigs(4).delaySpread  = params.channel.delaySpread.rural;
envConfigs(4).description  = 'Strong LoS, high Rician K-factor';

% Sample rate from system params
sampleRate = params.rf.sampleRate;

% Configure NTN-TDL channels for each environment
fprintf('  Configuring NTN-TDL channels (sample rate = %.2f MHz):\n', sampleRate/1e6);
fprintf('  %-14s | %-12s | Delay Spread | Description\n', 'Environment', 'Profile');
fprintf('  %s\n', repmat('-', 1, 75));

tdlChannels = cell(1, length(envConfigs));

for k = 1:length(envConfigs)
    tdl = nrTDLChannel;
    tdl.DelayProfile        = envConfigs(k).profile;
    tdl.DelaySpread         = envConfigs(k).delaySpread;
    tdl.MaximumDopplerShift = mobileDoppler;     % UE mobility only (fading)
    tdl.SampleRate          = sampleRate;
    tdl.NumTransmitAntennas = 1;
    tdl.NumReceiveAntennas  = 1;
    tdl.RandomStream        = params.channel.randomStream;
    tdl.Seed                = params.channel.seed;
    
    % Set satellite Doppler (frequency offset from orbit)
    % This property adds a deterministic frequency shift to the channel
    tdl.SatelliteDopplerShift = refSatDoppler;
    
    tdlChannels{k} = tdl;
    
    fprintf('  %-14s | %-12s | %6.0f ns    | %s\n', ...
        envConfigs(k).name, envConfigs(k).profile, ...
        envConfigs(k).delaySpread*1e9, envConfigs(k).description);
end
fprintf('\n');

fprintf('  NOTE: All channels use the SAME Doppler configuration.\n');
fprintf('  The difference between transparent/regenerative payloads is\n');
fprintf('  modeled in Phase 4 through signal chain, NOT channel profile.\n\n');

%% =====================================================================
%  SECTION 3: CHANNEL IMPULSE RESPONSE VISUALIZATION
%  =====================================================================
fprintf('--- Section 3: Generating channel impulse responses ---\n');

% Generate a short test signal to extract channel characteristics
testLen = round(sampleRate * 0.01);  % 10 ms of samples
testSig = complex(randn(testLen, 1), randn(testLen, 1)) / sqrt(2);

figure('Name', 'Channel Impulse Response', 'Position', [100 100 1100 700]);
colors = lines(4);

for k = 1:length(envConfigs)
    % Reset channel and pass test signal
    reset(tdlChannels{k});
    [rxSig, pathGains, sampleTimes] = tdlChannels{k}(testSig);
    
    % Get channel info for tap delays
    chInfo = info(tdlChannels{k});
    tapDelays_ns = chInfo.ChannelFilterDelay * (1e9 / sampleRate);
    
    % Power delay profile: average |pathGains|^2 over time
    % pathGains is [nSamples x nPaths x nTx x nRx]
    avgPower_dB = 10*log10(mean(abs(pathGains(:,:,1,1)).^2, 1));
    nPaths = size(pathGains, 2);
    pathIdx = 0:(nPaths-1);
    pathDelays_ns = pathIdx * (1e9 / sampleRate);  % Approximate tap spacing
    
    subplot(2, 2, k);
    stem(pathDelays_ns, avgPower_dB - max(avgPower_dB), 'filled', ...
        'Color', colors(k,:), 'LineWidth', 1.5, 'MarkerSize', 6);
    xlabel('Delay (ns)', 'FontSize', 10);
    ylabel('Normalized Power (dB)', 'FontSize', 10);
    title(sprintf('%s (%s, DS=%.0f ns)', ...
        envConfigs(k).name, envConfigs(k).profile, envConfigs(k).delaySpread*1e9), ...
        'FontSize', 11);
    grid on;
    set(gca, 'FontSize', 9);
    ylim([-35 5]);
    xlim([0 max(pathDelays_ns)*1.1 + 10]);
end
sgtitle('NTN-TDL Power Delay Profiles — 4 Environments', 'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase2_power_delay_profiles.png'));
fprintf('  Saved: phase2_power_delay_profiles.png\n');

%% =====================================================================
%  SECTION 4: SPECTRUM COMPARISON ACROSS ENVIRONMENTS
%  =====================================================================
fprintf('--- Section 4: Spectrum comparison ---\n');

% Generate longer test signal for spectrum analysis
specLen = round(sampleRate * 0.1);  % 100 ms
specSig = complex(randn(specLen, 1), randn(specLen, 1)) / sqrt(2);

figure('Name', 'Channel Spectra', 'Position', [100 100 1100 700]);

for k = 1:length(envConfigs)
    reset(tdlChannels{k});
    rxSpec = tdlChannels{k}(specSig);
    
    % Compute PSD using pwelch
    nfft = 2048;
    [pxx, f] = pwelch(rxSpec, hanning(nfft), nfft/2, nfft, sampleRate, 'centered');
    pxx_dB = 10*log10(pxx / max(pxx));
    f_MHz = f / 1e6;
    
    subplot(2, 2, k);
    plot(f_MHz, pxx_dB, 'Color', colors(k,:), 'LineWidth', 1.0);
    xlabel('Frequency (MHz)', 'FontSize', 10);
    ylabel('Normalized PSD (dB)', 'FontSize', 10);
    title(sprintf('%s (%s)', envConfigs(k).name, envConfigs(k).profile), 'FontSize', 11);
    grid on;
    set(gca, 'FontSize', 9);
    ylim([-40 5]);
end
sgtitle('NTN-TDL Channel Spectra — 4 Environments', 'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase2_channel_spectra.png'));
fprintf('  Saved: phase2_channel_spectra.png\n');

%% =====================================================================
%  SECTION 5: DOPPLER SHIFT vs ELEVATION PLOT
%  =====================================================================
fprintf('--- Section 5: Doppler vs Elevation ---\n');

figure('Name', 'Doppler vs Elevation', 'Position', [100 100 900 500]);
yyaxis left;
plot(elevSweep, satDoppler/1e3, '-bo', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'Satellite Orbital Doppler');
ylabel('Satellite Doppler (kHz)', 'FontSize', 12);

yyaxis right;
plot(elevSweep, mobileDoppler * ones(size(elevSweep)), '--rs', ...
    'LineWidth', 1.5, 'MarkerSize', 6, 'DisplayName', 'UE Mobility Doppler');
ylabel('UE Doppler (Hz)', 'FontSize', 12);

xlabel('Elevation Angle (deg)', 'FontSize', 12);
title('NTN Doppler Components vs Elevation — LEO 600 km, 2 GHz', 'FontSize', 13);
legend('Location', 'northeast', 'FontSize', 10);
grid on;
set(gca, 'FontSize', 11);
saveas(gcf, fullfile(params.outputDir, 'phase2_doppler_vs_elevation.png'));
fprintf('  Saved: phase2_doppler_vs_elevation.png\n');

%% =====================================================================
%  SECTION 6: P.681 NARROWBAND LMS CHANNEL (if available)
%  =====================================================================
fprintf('\n--- Section 6: P.681 Narrowband LMS Channel ---\n');

lmsChannels = {};
lmsEnvNames = {};

% Check if p681LMSChannel exists in this MATLAB version
hasP681 = exist('p681LMSChannel', 'class') == 8;

if hasP681
    fprintf('  p681LMSChannel available — configuring 3 environments.\n');
    
    lmsEnvs = {'Urban', 'RuralWooded', 'Suburban'};
    lmsLabels = {'P.681 Urban', 'P.681 Rural/Wooded', 'P.681 Suburban'};
    
    frameDuration = 0.02;        % 20 ms per frame
    numFrames     = 250;         % 5 seconds per environment
    frameLength   = round(sampleRate * frameDuration);
    
    % Store fading time-series for each environment
    lmsFading = cell(1, length(lmsEnvs));
    
    figure('Name', 'P.681 LMS Fading', 'Position', [100 100 1100 400]);
    
    for k = 1:length(lmsEnvs)
        chan = p681LMSChannel;
        chan.SampleRate          = sampleRate;
        chan.CarrierFrequency    = fc;
        chan.ElevationAngle      = refElev;
        chan.MobileSpeed         = params.ue.speed_ms;
        chan.SatelliteDopplerShift = refSatDoppler;
        chan.RandomStream        = params.channel.randomStream;
        chan.Seed                = params.channel.seed + k;  % Different seed per env
        chan.FadingTechnique     = "Sum of sinusoids";
        chan.NumSinusoids        = 48;
        chan.AzimuthOrientation  = 0;
        chan.Environment         = lmsEnvs{k};
        
        % Run channel and collect envelope
        envelope_dB = zeros(numFrames, 1);
        for f = 1:numFrames
            tx = complex(randn(frameLength, 1), randn(frameLength, 1)) / sqrt(2);
            rx = chan(tx);
            envelope_dB(f) = 10*log10(mean(abs(rx).^2) / mean(abs(tx).^2));
        end
        
        lmsFading{k} = envelope_dB;
        lmsChannels{k} = chan;
        lmsEnvNames{k} = lmsLabels{k};
        
        timeAxis = (0:numFrames-1) * frameDuration;
        
        subplot(1, 3, k);
        plot(timeAxis, envelope_dB, 'LineWidth', 0.8, 'Color', colors(k,:));
        xlabel('Time (s)', 'FontSize', 10);
        ylabel('Fading Envelope (dB)', 'FontSize', 10);
        title(lmsLabels{k}, 'FontSize', 11);
        grid on;
        set(gca, 'FontSize', 9);
        ylim([-30 5]);
        
        fprintf('    %s: mean=%.1f dB, std=%.1f dB\n', ...
            lmsLabels{k}, mean(envelope_dB), std(envelope_dB));
        
        release(chan);
    end
    sgtitle(sprintf('P.681 LMS Narrowband Fading — Elevation %d deg', refElev), ...
        'FontSize', 13, 'FontWeight', 'bold');
    saveas(gcf, fullfile(params.outputDir, 'phase2_p681_fading.png'));
    fprintf('  Saved: phase2_p681_fading.png\n');
else
    fprintf('  p681LMSChannel NOT available in this MATLAB version.\n');
    fprintf('  Skipping P.681 narrowband channel. This is optional.\n');
    fprintf('  The NTN-TDL wideband model (Section 2) is sufficient.\n');
end

%% =====================================================================
%  SECTION 7: CHANNEL COMPARISON — ENVIRONMENT IMPACT
%  =====================================================================
fprintf('\n--- Section 7: Channel comparison across environments ---\n');

% Pass identical signal through all 4 TDL channels and compare output
compLen = round(sampleRate * 0.05);  % 50 ms
compSig = complex(randn(compLen, 1), randn(compLen, 1)) / sqrt(2);
compTime = (0:compLen-1)' / sampleRate * 1e3;  % milliseconds

figure('Name', 'Channel Comparison', 'Position', [100 100 1100 500]);

subplot(1, 2, 1);
hold on;
legendEntries = {};
for k = 1:length(envConfigs)
    reset(tdlChannels{k});
    rxComp = tdlChannels{k}(compSig);
    envPower_dB = 10*log10(abs(rxComp).^2 + 1e-20);
    % Smooth for visibility
    windowLen = round(sampleRate * 0.001);  % 1 ms smoothing window
    envSmooth = movmean(envPower_dB, windowLen);
    plot(compTime, envSmooth, 'LineWidth', 1.0, 'Color', colors(k,:));
    legendEntries{k} = sprintf('%s (%s)', envConfigs(k).name, envConfigs(k).profile);
end
hold off;
xlabel('Time (ms)', 'FontSize', 11);
ylabel('Instantaneous Power (dB)', 'FontSize', 11);
title('Channel Fading — Time Domain', 'FontSize', 12);
legend(legendEntries, 'Location', 'southwest', 'FontSize', 8);
grid on;
set(gca, 'FontSize', 10);

% CDF of channel gain
subplot(1, 2, 2);
hold on;
for k = 1:length(envConfigs)
    reset(tdlChannels{k});
    rxCDF = tdlChannels{k}(compSig);
    gain_dB = 10*log10(abs(rxCDF).^2 + 1e-20);
    [fCDF, xCDF] = ecdf(gain_dB);
    plot(xCDF, fCDF, 'LineWidth', 1.5, 'Color', colors(k,:));
end
hold off;
xlabel('Channel Gain (dB)', 'FontSize', 11);
ylabel('CDF', 'FontSize', 11);
title('Channel Gain CDF — Environment Comparison', 'FontSize', 12);
legend(legendEntries, 'Location', 'northwest', 'FontSize', 8);
grid on;
set(gca, 'FontSize', 10);
xlim([-40 10]);

sgtitle('NTN-TDL Channel Comparison — Same Doppler, Different Environments', ...
    'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase2_channel_comparison.png'));
fprintf('  Saved: phase2_channel_comparison.png\n');

%% =====================================================================
%  SECTION 8: VALIDATION CHECKS
%  =====================================================================
fprintf('\n--- Section 8: Validation checks ---\n');

% Check 1: Satellite Doppler range
fprintf('  [CHECK] Sat Doppler at 10 deg = %.1f kHz (expected 24-48 kHz)... ', satDoppler(1)/1e3);
if satDoppler(1)/1e3 > 20 && satDoppler(1)/1e3 < 55
    fprintf('PASS\n');
else
    fprintf('WARNING\n');
end

% Check 2: Sat Doppler at zenith should be ~0
fprintf('  [CHECK] Sat Doppler at 90 deg = %.1f kHz (expected ~0)... ', satDoppler(end)/1e3);
if abs(satDoppler(end)/1e3) < 2
    fprintf('PASS\n');
else
    fprintf('WARNING\n');
end

% Check 3: UE mobility Doppler
fprintf('  [CHECK] UE Doppler = %.1f Hz (expected ~5.6 Hz at 3km/h, 2GHz)... ', mobileDoppler);
if mobileDoppler > 4 && mobileDoppler < 8
    fprintf('PASS\n');
else
    fprintf('WARNING\n');
end

% Check 4: Channel objects created
fprintf('  [CHECK] NTN-TDL channels configured: %d (expected 4)... ', length(tdlChannels));
if length(tdlChannels) == 4
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('\n');

%% =====================================================================
%  SECTION 9: EXPORT RESULTS FOR PHASE 3+
%  =====================================================================
fprintf('--- Section 9: Exporting results ---\n');

phase2 = struct();

% Doppler data
phase2.elevSweep       = elevSweep;        % [deg]
phase2.satDoppler      = satDoppler;        % [Hz] per elevation
phase2.mobileDoppler   = mobileDoppler;     % [Hz] constant
phase2.refElev         = refElev;           % [deg] reference elevation
phase2.refSatDoppler   = refSatDoppler;     % [Hz] at reference elevation

% Environment configurations
phase2.envConfigs      = envConfigs;        % Struct array with profile/delay spread
phase2.sampleRate      = sampleRate;        % [Hz]

% Channel objects (for reuse in Phase 3+)
phase2.tdlChannels     = tdlChannels;       % Cell array of nrTDLChannel objects

% P.681 channels (if available)
phase2.hasP681         = hasP681;
phase2.lmsChannels     = lmsChannels;
phase2.lmsEnvNames     = lmsEnvNames;

% Carrier frequency and speed for downstream use
phase2.carrierFreq     = fc;
phase2.ueSpeed         = params.ue.speed_ms;

outFile = fullfile(params.outputDir, 'phase2_results.mat');
save(outFile, 'phase2', '-v7.3');
fprintf('  Saved: %s\n', outFile);

%% =====================================================================
%  SUMMARY
%  =====================================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 2 COMPLETE\n');
fprintf('============================================================\n');
fprintf('  NTN-TDL channels: 4 environments configured\n');
fprintf('    NTN-TDL-A (Dense Urban) : DS = %.0f ns\n', envConfigs(1).delaySpread*1e9);
fprintf('    NTN-TDL-B (Urban)       : DS = %.0f ns\n', envConfigs(2).delaySpread*1e9);
fprintf('    NTN-TDL-C (Suburban)    : DS = %.0f ns\n', envConfigs(3).delaySpread*1e9);
fprintf('    NTN-TDL-D (Rural)       : DS = %.0f ns\n', envConfigs(4).delaySpread*1e9);
fprintf('  Satellite Doppler range: %.1f kHz (10 deg) to %.1f kHz (90 deg)\n', ...
    satDoppler(1)/1e3, satDoppler(end)/1e3);
fprintf('  UE mobility Doppler: %.1f Hz\n', mobileDoppler);
if hasP681
    fprintf('  P.681 LMS channels: 3 environments configured\n');
end
fprintf('\n  IMPORTANT: Both transparent and regenerative payloads\n');
fprintf('  use the SAME channel profile for a given environment.\n');
fprintf('  Payload differences are modeled in Phase 4.\n');
fprintf('\n  Load in Phase 3: load(''results/phase2_results.mat'')\n');
fprintf('============================================================\n');
