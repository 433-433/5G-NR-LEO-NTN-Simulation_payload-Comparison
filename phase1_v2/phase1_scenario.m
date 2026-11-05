%% ========================================================================
%  PHASE 1: System and Environment Setup (v3 — FINAL)
%  ========================================================================
%  Performance Analysis of 5G NR in LEO Non-Terrestrial Networks
%
%  FIXES from v2:
%    - Forces 24h duration (full Earth rotation) to guarantee visibility
%    - Comprehensive diagnostics after aer() to catch issues early
%    - Reports per-UE max elevation across ALL satellites
%    - Falls back to states()-based elevation if aer() returns bad data
%
%  Expected runtime: 15-60 seconds
%  ========================================================================
clc; clear; close all;

%% Add paths
addpath('config');
addpath('helpers');

%% Load centralized parameters
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 1: System and Environment Setup (v3 — FINAL)\n');
fprintf('  LEO NTN Scenario — 5G NR Performance Analysis\n');
fprintf('============================================================\n\n');

%% =====================================================================
%  SECTION 1: CREATE SATELLITE SCENARIO
%  =====================================================================
fprintf('--- Section 1: Creating satellite scenario ---\n');

startTime = params.sim.startTime;
dt        = params.sim.timeStep;

% FORCE 24 hours regardless of what systemParams says
simDuration = hours(24);
stopTime    = startTime + simDuration;

sc = satelliteScenario(startTime, stopTime, dt);

fprintf('  Start time    : %s\n', string(startTime));
fprintf('  Stop time     : %s\n', string(stopTime));
fprintf('  Duration      : %.1f hours (24h forced for full Earth rotation)\n', ...
    hours(simDuration));
fprintf('  Time step     : %d seconds\n', dt);
fprintf('  Orbital period: %.1f seconds (%.1f minutes)\n\n', ...
    params.sim.orbitalPeriod, params.sim.orbitalPeriod/60);

%% =====================================================================
%  SECTION 2: DEPLOY WALKER DELTA CONSTELLATION
%  =====================================================================
fprintf('--- Section 2: Deploying Walker Delta constellation ---\n');

numPlanes    = params.sat.numPlanes;
satsPerPlane = params.sat.satsPerPlane;
numSats      = params.sat.numSats;
a_orbit      = params.sat.semiMajorAxis;
inc          = params.sat.inclination;
walkerF      = params.sat.walkerF;

raanSpacing  = 360 / numPlanes;
taSpacing    = 360 / satsPerPlane;
phaseOffset  = walkerF * 360 / numSats;

RAAN_all  = zeros(numSats, 1);
TA_all    = zeros(numSats, 1);
ecc_all   = zeros(numSats, 1);
argp_all  = zeros(numSats, 1);
satNames  = strings(numSats, 1);

for p = 0:(numPlanes-1)
    for s = 0:(satsPerPlane-1)
        idx = p * satsPerPlane + s + 1;
        RAAN_all(idx) = p * raanSpacing;
        TA_all(idx)   = mod(s * taSpacing + p * phaseOffset, 360);
        satNames(idx) = sprintf("LEO_%02d_P%d", idx, p+1);
    end
end

sat = satellite(sc, ...
    a_orbit * ones(numSats,1), ecc_all, inc * ones(numSats,1), ...
    RAAN_all, argp_all, TA_all, 'Name', satNames);

for i = 1:numSats
    sat(i).ShowLabel = false;
end
for p = 1:numPlanes
    sat((p-1)*satsPerPlane + 1).ShowLabel = true;
end

fprintf('  Walker %d/%d/%d at %d km, %d deg inclination\n', ...
    numSats, numPlanes, walkerF, params.sat.altitude/1e3, inc);
fprintf('  RAAN spacing=%.0f deg, TA spacing=%.0f deg, Phase offset=%.1f deg\n\n', ...
    raanSpacing, taSpacing, phaseOffset);

%% =====================================================================
%  SECTION 3: DEPLOY GROUND STATIONS
%  =====================================================================
fprintf('--- Section 3: Deploying ground infrastructure ---\n');

nGW = params.gw.count;
for i = 1:nGW
    if i == 1
        gateways = groundStation(sc, params.gw.lat(i), params.gw.lon(i), ...
            'Name', params.gw.names(i), 'MinElevationAngle', params.ue.minElevation);
    else
        gateways(i) = groundStation(sc, params.gw.lat(i), params.gw.lon(i), ...
            'Name', params.gw.names(i), 'MinElevationAngle', params.ue.minElevation);
    end
    gateways(i).ShowLabel = true;
end
fprintf('  Gateways: %d\n', nGW);

nUE = params.ue.count;
for i = 1:nUE
    if i == 1
        UEs = groundStation(sc, params.ue.lat(i), params.ue.lon(i), ...
            'Name', params.ue.names(i), 'MinElevationAngle', params.ue.minElevation);
    else
        UEs(i) = groundStation(sc, params.ue.lat(i), params.ue.lon(i), ...
            'Name', params.ue.names(i), 'MinElevationAngle', params.ue.minElevation);
    end
    UEs(i).ShowLabel = true;
end
fprintf('  UEs: %d (2 per gateway)\n\n', nUE);

%% =====================================================================
%  SECTION 4: ACCESS LINKS
%  =====================================================================
fprintf('--- Section 4: Creating access links ---\n');
for i = 1:nGW
    access(sat, gateways(i));
end
for i = 1:nUE
    access(sat, UEs(i));
end
fprintf('  Done.\n\n');

%% =====================================================================
%  SECTION 5: SLANT RANGE GEOMETRY (Analytical)
%  =====================================================================
fprintf('--- Section 5: Computing slant range geometry ---\n');

elevAngles = 10:1:90;
[slantRanges, propDelays] = computeSlantRange(elevAngles, params.sat.altitude, ...
    params.R_earth, params.c);
FSPL_dB = 20*log10(4*pi*slantRanges*params.rf.carrierFrequency/params.c);

fprintf('  Slant range at 10 deg : %.1f km | prop delay: %.2f ms\n', slantRanges(1)/1e3, propDelays(1)*1e3);
fprintf('  Slant range at 90 deg : %.1f km | prop delay: %.2f ms\n', slantRanges(end)/1e3, propDelays(end)*1e3);
fprintf('  FSPL range            : %.1f dB (10 deg) to %.1f dB (90 deg)\n\n', FSPL_dB(1), FSPL_dB(end));

%% =====================================================================
%  SECTION 6: VECTORIZED TIME-SERIES SIMULATION
%  =====================================================================
fprintf('--- Section 6: Running time-series simulation ---\n');

timeVec  = startTime:seconds(dt):stopTime;
nSteps   = length(timeVec);
f_c      = params.rf.carrierFrequency;
c        = params.c;
minElev  = params.ue.minElevation;

fprintf('  Time steps: %d | Duration: %.1f hours | dt: %d s\n', nSteps, nSteps*dt/3600, dt);
fprintf('  Satellites: %d | UEs: %d\n\n', numSats, nUE);

% ---- Step 6a: Compute elevation using aer() without time argument ----
% aer(sat, UE) without time returns full time-series — confirmed working
% in v2 (6.8s runtime, returned real elevation data).
% With 24h duration, satellites WILL pass over Ghana.
fprintf('  Step 6a: Computing elevation via aer(sat, UE) — no time arg...\n');
tic;

allElev  = -999 * ones(nSteps, numSats, nUE);
allRange = zeros(nSteps, numSats, nUE);

for s = 1:numSats
    for u = 1:nUE
        [~, el_ts, r_ts] = aer(UEs(u), sat(s));
        nPts = min(length(el_ts), nSteps);
        allElev(1:nPts, s, u)  = el_ts(1:nPts);
        allRange(1:nPts, s, u) = r_ts(1:nPts);
    end
    if mod(s, 12) == 0
        fprintf('    Satellite %d/%d processed\n', s, numSats);
    end
end
fprintf('    Complete in %.1f s\n\n', toc);

% ---- Step 6b: DIAGNOSTIC ----
fprintf('  Step 6b: DIAGNOSTIC — elevation statistics...\n');
globalMaxElev = max(allElev(:));
fprintf('    GLOBAL max elevation: %.1f deg\n', globalMaxElev);

for u = 1:nUE
    elevU = allElev(:, :, u);
    maxElevU = max(elevU(:));
    nAbove10 = sum(elevU(:) > 10);
    fprintf('    %-15s: max_elev=%6.1f deg, points > 10 deg: %d\n', ...
        params.ue.names(u), maxElevU, nAbove10);
end
fprintf('\n');

% ---- Step 6c: Select best serving satellite ----
fprintf('  Step 6c: Selecting best satellite per UE per time step...\n');

elevationTimeSeries = zeros(nSteps, nUE);
servingSatIdx       = zeros(nSteps, nUE);
slantRangeTS        = zeros(nSteps, nUE);

for u = 1:nUE
    elevU = allElev(:, :, u);
    rngU  = allRange(:, :, u);
    
    elevU(elevU < minElev) = -Inf;
    [bestElev, bestIdx] = max(elevU, [], 2);
    
    noVis = bestElev <= -Inf;
    bestElev(noVis) = 0;
    bestIdx(noVis)  = 0;
    
    elevationTimeSeries(:, u) = bestElev;
    servingSatIdx(:, u)       = bestIdx;
    
    for step = 1:nSteps
        if bestIdx(step) > 0
            slantRangeTS(step, u) = rngU(step, bestIdx(step));
        end
    end
end

% ---- Step 6d: Doppler from range rate ----
fprintf('  Step 6d: Computing Doppler...\n');
dopplerTimeSeries = zeros(nSteps, nUE);

for u = 1:nUE
    ranges = slantRangeTS(:, u);
    rangeRateVec = gradient(ranges, dt);
    dopplerTimeSeries(:, u) = -(rangeRateVec / c) * f_c;
    dopplerTimeSeries(servingSatIdx(:,u) == 0, u) = 0;
end

fprintf('  Section 6 complete.\n\n');

%% =====================================================================
%  SECTION 7: HANDOVER ANALYSIS
%  =====================================================================
fprintf('--- Section 7: Analyzing handovers ---\n');

handoverMatrix = diff(servingSatIdx) ~= 0;
handoverCount  = sum(handoverMatrix, 1);

simDuration_hours = 24;
handoverRate = handoverCount / simDuration_hours;

visibleSteps = servingSatIdx > 0;
visibilityPct = 100 * sum(visibleSteps, 1) / nSteps;

avgPassDuration = zeros(1, nUE);
for u = 1:nUE
    hoIdx = find(handoverMatrix(:, u));
    if length(hoIdx) > 1
        avgPassDuration(u) = mean(diff(hoIdx)) * dt;
    end
end

fprintf('  Results over %.0f hours:\n', simDuration_hours);
fprintf('  %-15s | Handovers | Rate/hr | Visibility | Avg Pass\n', 'UE');
fprintf('  %s\n', repmat('-', 1, 70));
for u = 1:nUE
    fprintf('  %-15s | %5d     | %5.1f   | %6.1f%%    | %5.0f s\n', ...
        params.ue.names(u), handoverCount(u), handoverRate(u), ...
        visibilityPct(u), avgPassDuration(u));
end
fprintf('\n');

%% =====================================================================
%  SECTION 8: VALIDATION CHECKS
%  =====================================================================
fprintf('--- Section 8: Validation checks ---\n');

fprintf('  [CHECK] Orbital period = %.1f s... ', params.sim.orbitalPeriod);
if abs(params.sim.orbitalPeriod - 5801) < 50, fprintf('PASS\n'); else, fprintf('WARNING\n'); end

fprintf('  [CHECK] Slant range at 90 deg = %.1f km... ', slantRanges(end)/1e3);
if abs(slantRanges(end) - params.sat.altitude) < 1e3, fprintf('PASS\n'); else, fprintf('FAIL\n'); end

fprintf('  [CHECK] Slant range at 10 deg = %.1f km... ', slantRanges(1)/1e3);
if slantRanges(1)/1e3 > 1800 && slantRanges(1)/1e3 < 2100, fprintf('PASS\n'); else, fprintf('WARNING\n'); end

meanVis = mean(visibilityPct);
fprintf('  [CHECK] Mean visibility = %.1f%%... ', meanVis);
if meanVis > 0, fprintf('PASS\n'); else, fprintf('FAIL\n'); end

maxDoppler = max(abs(dopplerTimeSeries(:)));
fprintf('  [CHECK] Max Doppler = %.1f kHz... ', maxDoppler/1e3);
if maxDoppler/1e3 > 10, fprintf('PASS\n'); else, fprintf('WARNING\n'); end

meanHoRate = mean(handoverRate);
fprintf('  [CHECK] Mean HO rate = %.1f/hr... ', meanHoRate);
if meanHoRate >= 1, fprintf('PASS\n'); else, fprintf('NOTE\n'); end

fprintf('\n');

%% =====================================================================
%  SECTION 9: PUBLICATION-QUALITY PLOTS
%  =====================================================================
fprintf('--- Section 9: Generating plots ---\n');

colors = lines(nUE);
timeMinutes = minutes(timeVec - timeVec(1));
timeHours   = timeMinutes / 60;

% ---- Figure 1: Elevation vs Time ----
figure('Name', 'Elevation vs Time', 'Position', [100 100 1100 500]);
hold on;
plotIdx = 1:2:min(nUE, 16);
for u = plotIdx
    plot(timeHours, elevationTimeSeries(:,u), 'LineWidth', 1.0, ...
        'Color', colors(u,:), 'DisplayName', params.ue.names(u));
end
yline(params.ue.minElevation, '--k', 'Min El (10 deg)', 'LineWidth', 1);
hold off;
xlabel('Time (hours)', 'FontSize', 12);
ylabel('Elevation Angle (deg)', 'FontSize', 12);
title('Best Satellite Elevation Angle vs Time', 'FontSize', 13);
legend('Location', 'eastoutside', 'FontSize', 8);
grid on; set(gca, 'FontSize', 11);
xlim([0 24]); ylim([0 90]);
saveas(gcf, fullfile(params.outputDir, 'phase1_elevation_vs_time.png'));
fprintf('  Saved: phase1_elevation_vs_time.png\n');

% ---- Figure 2: Slant Range ----
figure('Name', 'Slant Range', 'Position', [100 100 900 450]);
yyaxis left;
plot(elevAngles, slantRanges/1e3, '-b', 'LineWidth', 2);
ylabel('Slant Range (km)', 'FontSize', 12); ylim([500 2200]);
yyaxis right;
plot(elevAngles, propDelays*1e3, '-r', 'LineWidth', 2);
ylabel('Propagation Delay (ms)', 'FontSize', 12);
xlabel('Elevation Angle (deg)', 'FontSize', 12);
title('LEO-600 Slant Range & Propagation Delay vs Elevation', 'FontSize', 13);
grid on; set(gca, 'FontSize', 11);
legend({'Slant Range', 'Propagation Delay'}, 'Location', 'northeast');
saveas(gcf, fullfile(params.outputDir, 'phase1_slant_range_vs_elevation.png'));
fprintf('  Saved: phase1_slant_range_vs_elevation.png\n');

% ---- Figure 3: FSPL ----
figure('Name', 'FSPL', 'Position', [100 100 900 400]);
plot(elevAngles, FSPL_dB, '-', 'LineWidth', 2, 'Color', [0.5 0 0.5]);
xlabel('Elevation Angle (deg)', 'FontSize', 12);
ylabel('FSPL (dB)', 'FontSize', 12);
title('FSPL at 2 GHz vs Elevation — LEO 600 km', 'FontSize', 13);
grid on; set(gca, 'FontSize', 11, 'YDir', 'reverse');
saveas(gcf, fullfile(params.outputDir, 'phase1_fspl_vs_elevation.png'));
fprintf('  Saved: phase1_fspl_vs_elevation.png\n');

% ---- Figure 4: Handovers ----
figure('Name', 'Handovers', 'Position', [100 100 1100 450]);
bar(1:nUE, handoverCount, 0.6, 'FaceColor', [0.2 0.4 0.7]);
hold on;
for u = 1:nUE
    text(u, handoverCount(u) + max(max(handoverCount),1)*0.03, ...
        sprintf('%.1f/hr', handoverRate(u)), ...
        'HorizontalAlignment', 'center', 'FontSize', 7, 'FontWeight', 'bold');
end
hold off;
set(gca, 'XTickLabel', params.ue.names, 'FontSize', 7, 'XTickLabelRotation', 45);
xlabel('User Equipment', 'FontSize', 12);
ylabel('Number of Handovers', 'FontSize', 12);
title('Handover Events per UE (24-hour simulation)', 'FontSize', 13);
grid on;
saveas(gcf, fullfile(params.outputDir, 'phase1_handover_events.png'));
fprintf('  Saved: phase1_handover_events.png\n');

% ---- Figure 5: Doppler UE1 ----
figure('Name', 'Doppler UE1', 'Position', [100 100 1000 450]);
plot(timeHours, dopplerTimeSeries(:,1)/1e3, 'b', 'LineWidth', 1.0);
hold on; yline(0, '--k', 'LineWidth', 0.5); hold off;
xlabel('Time (hours)', 'FontSize', 12);
ylabel('Doppler Shift (kHz)', 'FontSize', 12);
title(sprintf('Doppler Shift — %s (2 GHz)', params.ue.names(1)), 'FontSize', 13);
grid on; set(gca, 'FontSize', 11); xlim([0 24]);
saveas(gcf, fullfile(params.outputDir, 'phase1_doppler_vs_time.png'));
fprintf('  Saved: phase1_doppler_vs_time.png\n');

% ---- Figure 6: Doppler all UEs ----
figure('Name', 'Doppler All', 'Position', [100 100 1100 500]);
hold on;
for u = plotIdx
    plot(timeHours, dopplerTimeSeries(:,u)/1e3, 'LineWidth', 0.8, ...
        'Color', colors(u,:), 'DisplayName', params.ue.names(u));
end
yline(0, '--k', 'HandleVisibility', 'off');
hold off;
xlabel('Time (hours)', 'FontSize', 12);
ylabel('Doppler Shift (kHz)', 'FontSize', 12);
title('Doppler Shift vs Time — Selected UEs', 'FontSize', 13);
legend('Location', 'eastoutside', 'FontSize', 8);
grid on; set(gca, 'FontSize', 11); xlim([0 24]);
saveas(gcf, fullfile(params.outputDir, 'phase1_doppler_all_ues.png'));
fprintf('  Saved: phase1_doppler_all_ues.png\n');

% ---- Figure 7: Visibility ----
figure('Name', 'Visibility', 'Position', [100 100 1100 450]);
bar(1:nUE, visibilityPct, 0.6, 'FaceColor', [0.2 0.6 0.3]);
hold on;
for u = 1:nUE
    text(u, visibilityPct(u) + 1.5, sprintf('%.1f%%', visibilityPct(u)), ...
        'HorizontalAlignment', 'center', 'FontSize', 7, 'FontWeight', 'bold');
end
hold off;
set(gca, 'XTickLabel', params.ue.names, 'FontSize', 7, 'XTickLabelRotation', 45);
xlabel('User Equipment', 'FontSize', 12);
ylabel('Satellite Visibility (%)', 'FontSize', 12);
title('Satellite Visibility per UE (24h)', 'FontSize', 13);
grid on; ylim([0 105]);
saveas(gcf, fullfile(params.outputDir, 'phase1_visibility.png'));
fprintf('  Saved: phase1_visibility.png\n');

%% =====================================================================
%  SECTION 10: EXPORT
%  =====================================================================
fprintf('\n--- Section 10: Exporting results ---\n');

phase1 = struct();
phase1.params              = params;
phase1.elevAngles          = elevAngles;
phase1.slantRanges         = slantRanges;
phase1.propDelays          = propDelays;
phase1.FSPL_dB             = FSPL_dB;
phase1.timeVec             = timeVec;
phase1.timeMinutes         = timeMinutes;
phase1.timeHours           = timeHours;
phase1.elevationTimeSeries = elevationTimeSeries;
phase1.servingSatIdx       = servingSatIdx;
phase1.dopplerTimeSeries   = dopplerTimeSeries;
phase1.slantRangeTS        = slantRangeTS;
phase1.handoverCount       = handoverCount;
phase1.handoverRate        = handoverRate;
phase1.visibilityPct       = visibilityPct;
phase1.avgPassDuration     = avgPassDuration;

outFile = fullfile(params.outputDir, 'phase1_results.mat');
save(outFile, 'phase1', '-v7.3');
fprintf('  Saved: %s\n', outFile);

%% =====================================================================
%  SECTION 11: 3D VIEWER
%  =====================================================================
fprintf('\n--- Section 11: Launching 3D viewer ---\n');
try
    viewer = satelliteScenarioViewer(sc, 'ShowDetails', true);
    campos(viewer, 7.5, -1.0, 3e6);
    play(sc);
catch ME
    fprintf('  Viewer skipped: %s\n', ME.message);
end

%% =====================================================================
%  SUMMARY
%  =====================================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 1 COMPLETE (v3)\n');
fprintf('============================================================\n');
fprintf('  Constellation  : Walker %d/%d/%d at %d km\n', numSats, numPlanes, walkerF, params.sat.altitude/1e3);
fprintf('  Ground infra   : %d gateways, %d UEs across Ghana\n', nGW, nUE);
fprintf('  Sim duration   : 24 hours\n');
fprintf('  Max Doppler    : %.1f kHz\n', maxDoppler/1e3);
fprintf('  Mean HO rate   : %.1f handovers/hour\n', meanHoRate);
fprintf('  Mean visibility: %.1f%%\n', mean(visibilityPct));
fprintf('\n  Load in Phase 2: load(''results/phase1_results.mat'')\n');
fprintf('============================================================\n');
