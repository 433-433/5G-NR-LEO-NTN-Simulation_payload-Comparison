%% ========================================================================
%  PHASE 5: Latency Analysis
%  ========================================================================
%  Performance Analysis of 5G NR in LEO Non-Terrestrial Networks
%
%  Computes component-level latency budget for both payload architectures
%  per 3GPP TR 38.821 Section 7.2.
%
%  Latency components:
%    1. UE processing (encode + modulate)
%    2. Propagation: UE → Satellite (slant range dependent)
%    3. Satellite processing (transparent ≈ 0, regenerative = decode+re-encode)
%    4. Propagation: Satellite → Gateway (transparent only)
%    5. Gateway processing
%    6. Scheduling delay (BSR + grant, SCS dependent)
%    7. HARQ RTT (disabled for transparent, extended for regenerative)
%
%  Outputs:
%    4 publication figures + phase5_results.mat
%
%  3GPP References:
%    TR 38.821 Sec 7.2, Table 7.2-1  — NTN latency components
%    TR 38.821 Sec 7.1               — Timing advance
%    TR 38.821 Sec 7.3               — HARQ for NTN
%    TS 38.214 Sec 5                 — UE processing times
%  ========================================================================
clc; clear; close all;

%% Add paths and load previous results
addpath('config');
addpath('helpers');
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 5: Latency Analysis\n');
fprintf('  LEO NTN — 5G NR Performance Analysis\n');
fprintf('============================================================\n\n');

% Load Phase 1 and Phase 4 results
load(fullfile(params.outputDir, 'phase1_results.mat'), 'phase1');
load(fullfile(params.outputDir, 'phase4_results.mat'), 'phase4');
fprintf('  Phase 1 (geometry) and Phase 4 (payload) loaded.\n\n');

%% =====================================================================
%  SECTION 1: LATENCY COMPONENT DEFINITIONS
%  =====================================================================
fprintf('--- Section 1: Latency Component Definitions ---\n');

% --- Fixed processing delays (TR 38.821 Table 7.2-1) ---
T_UE_proc_ms    = 1.0;     % UE encoding + modulation [ms]
T_GW_proc_ms    = 1.5;     % Gateway processing [ms]

% Satellite processing depends on payload type:
T_sat_transp_ms = 0.1;     % Transparent: minimal (frequency translation + amplification)
T_sat_regen_ms  = 4.0;     % Regenerative: decode + re-encode + baseband processing

% Scheduling delay depends on SCS (number of slots for BSR + grant)
% Typically 4 slots: BSR (1 slot) + processing (1 slot) + grant (1 slot) + data (1 slot)
nSchedSlots = 4;

% HARQ parameters
% Transparent: HARQ disabled (RTT too long per TR 38.821 Sec 7.3)
% Regenerative: HARQ with K1 = 4-8 slots
harq_K1_slots = 6;     % Feedback delay in slots
harq_nMaxReTx = 3;     % Max retransmissions for regenerative

fprintf('  Fixed delays:\n');
fprintf('    UE processing      : %.1f ms\n', T_UE_proc_ms);
fprintf('    GW processing      : %.1f ms\n', T_GW_proc_ms);
fprintf('    Sat (transparent)  : %.1f ms\n', T_sat_transp_ms);
fprintf('    Sat (regenerative) : %.1f ms\n', T_sat_regen_ms);
fprintf('    Scheduling slots   : %d\n', nSchedSlots);
fprintf('    HARQ K1 (regen)    : %d slots\n', harq_K1_slots);
fprintf('    HARQ disabled for transparent (RTT exceeds timer)\n\n');

%% =====================================================================
%  SECTION 2: LATENCY vs ELEVATION ANGLE
%  =====================================================================
fprintf('--- Section 2: Latency vs Elevation Angle ---\n');

elevSweep = 10:2:90;
nElev     = length(elevSweep);
c         = params.c;

% Compute slant range and propagation delay for each elevation
[slantRange_m, propDelay_s] = computeSlantRange(elevSweep, params.sat.altitude, ...
    params.R_earth, c);
propDelay_ms = propDelay_s * 1e3;

% SCS values for scheduling delay
scsValues = [15, 30, 60, 120];
nSCS = length(scsValues);

% Compute per-component latency for EACH SCS and EACH elevation
% Store results: [nElev x nSCS] matrices

% One-way user plane latency (ms)
lat_transparent = zeros(nElev, nSCS);
lat_regenerative = zeros(nElev, nSCS);

% Component breakdown at reference elevation (50 deg) for each SCS
refElevIdx = find(elevSweep == 50, 1);
if isempty(refElevIdx)
    [~, refElevIdx] = min(abs(elevSweep - 50));
end

fprintf('  %-6s | %-8s | %-10s | %-10s | %-10s | %-10s\n', ...
    'SCS', 'Slot(ms)', 'Sched(ms)', 'Transp(ms)', 'Regen(ms)', 'Diff(ms)');
fprintf('  %s\n', repmat('-', 1, 65));

for s = 1:nSCS
    scs = scsValues(s);
    slotDur_ms = 1 / (2^(log2(scs/15)));  % Slot duration in ms
    schedDelay_ms = nSchedSlots * slotDur_ms;
    
    for e = 1:nElev
        % ---- Transparent Payload Latency ----
        % Path: UE → Sat → GW (two hops)
        % Propagation: UE→Sat + Sat→GW (both = slant range, conservative)
        prop_transp = 2 * propDelay_ms(e);  % Two-hop propagation
        
        lat_transparent(e, s) = T_UE_proc_ms + ...     % UE processing
                                 prop_transp + ...       % Two-hop propagation
                                 T_sat_transp_ms + ...   % Satellite (amplify only)
                                 T_GW_proc_ms + ...      % Gateway processing
                                 schedDelay_ms;           % Scheduling
        % NOTE: No HARQ for transparent (disabled)
        
        % ---- Regenerative Payload Latency ----
        % Path: UE → Sat (single hop for user plane)
        prop_regen = propDelay_ms(e);  % Single-hop propagation
        
        lat_regenerative(e, s) = T_UE_proc_ms + ...     % UE processing
                                  prop_regen + ...        % Single-hop propagation
                                  T_sat_regen_ms + ...    % Satellite (full processing)
                                  schedDelay_ms;           % Scheduling
        % NOTE: HARQ enabled but only adds latency on retransmission
    end
    
    % Print summary at reference elevation
    fprintf('  %-6d | %-8.3f | %-10.2f | %-10.2f | %-10.2f | %-10.2f\n', ...
        scs, slotDur_ms, schedDelay_ms, ...
        lat_transparent(refElevIdx, s), lat_regenerative(refElevIdx, s), ...
        lat_transparent(refElevIdx, s) - lat_regenerative(refElevIdx, s));
end
fprintf('\n');

%% =====================================================================
%  SECTION 3: LATENCY COMPONENT BREAKDOWN (Stacked Bar)
%  =====================================================================
fprintf('--- Section 3: Latency component breakdown ---\n');

% At reference elevation, 15 kHz SCS
refElev = elevSweep(refElevIdx);
refPropDelay = propDelay_ms(refElevIdx);
scs15_slot_ms = 1.0;
scs15_sched_ms = nSchedSlots * scs15_slot_ms;

% Component vectors [UE_proc, Prop_UE_Sat, Sat_proc, Prop_Sat_GW, GW_proc, Scheduling]
comp_transp = [T_UE_proc_ms, refPropDelay, T_sat_transp_ms, refPropDelay, T_GW_proc_ms, scs15_sched_ms];
comp_regen  = [T_UE_proc_ms, refPropDelay, T_sat_regen_ms,  0,            0,             scs15_sched_ms];

compLabels = {'UE Processing', 'Prop: UE→Sat', 'Sat Processing', ...
              'Prop: Sat→GW', 'GW Processing', 'Scheduling'};

figure('Name', 'Latency Breakdown', 'Position', [100 100 900 500]);
barData = [comp_transp; comp_regen];
bh = bar(barData, 'stacked');

% Color scheme
barColors = [0.2 0.6 0.9;   % UE proc (blue)
             0.9 0.4 0.1;   % Prop UE-Sat (orange)
             0.5 0.2 0.7;   % Sat proc (purple)
             0.9 0.7 0.2;   % Prop Sat-GW (yellow)
             0.3 0.7 0.3;   % GW proc (green)
             0.6 0.6 0.6];  % Scheduling (gray)
for i = 1:length(bh)
    bh(i).FaceColor = barColors(i,:);
end

set(gca, 'XTickLabel', {'Transparent', 'Regenerative'}, 'FontSize', 12);
ylabel('One-Way Latency (ms)', 'FontSize', 12);
title(sprintf('Latency Component Breakdown — %d deg Elevation, 15 kHz SCS', refElev), 'FontSize', 13);
legend(compLabels, 'Location', 'eastoutside', 'FontSize', 9);
grid on;
set(gca, 'FontSize', 11);

% Add total label on top of each bar
totals = sum(barData, 2);
for k = 1:2
    text(k, totals(k) + 0.3, sprintf('Total: %.1f ms', totals(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
end

saveas(gcf, fullfile(params.outputDir, 'phase5_latency_breakdown.png'));
fprintf('  Saved: phase5_latency_breakdown.png\n');

fprintf('  At %d deg elevation (15 kHz SCS):\n', refElev);
fprintf('    Transparent total : %.1f ms\n', sum(comp_transp));
fprintf('    Regenerative total: %.1f ms\n', sum(comp_regen));
fprintf('    Difference        : %.1f ms (%.0f%% reduction)\n\n', ...
    sum(comp_transp) - sum(comp_regen), ...
    100*(sum(comp_transp) - sum(comp_regen))/sum(comp_transp));

%% =====================================================================
%  SECTION 4: LATENCY vs ELEVATION — BOTH PAYLOADS
%  =====================================================================
fprintf('--- Section 4: Latency vs Elevation plots ---\n');

figure('Name', 'Latency vs Elevation', 'Position', [100 100 1100 500]);

subplot(1, 2, 1);
hold on;
colors = lines(nSCS);
for s = 1:nSCS
    plot(elevSweep, lat_transparent(:, s), '-o', 'LineWidth', 1.5, ...
        'MarkerSize', 4, 'Color', colors(s,:), ...
        'DisplayName', sprintf('SCS %d kHz', scsValues(s)));
end
hold off;
xlabel('Elevation Angle (deg)', 'FontSize', 12);
ylabel('One-Way Latency (ms)', 'FontSize', 12);
title('Transparent Payload', 'FontSize', 13);
legend('Location', 'northeast', 'FontSize', 9);
grid on; set(gca, 'FontSize', 11);

subplot(1, 2, 2);
hold on;
for s = 1:nSCS
    plot(elevSweep, lat_regenerative(:, s), '-s', 'LineWidth', 1.5, ...
        'MarkerSize', 4, 'Color', colors(s,:), ...
        'DisplayName', sprintf('SCS %d kHz', scsValues(s)));
end
hold off;
xlabel('Elevation Angle (deg)', 'FontSize', 12);
ylabel('One-Way Latency (ms)', 'FontSize', 12);
title('Regenerative Payload', 'FontSize', 13);
legend('Location', 'northeast', 'FontSize', 9);
grid on; set(gca, 'FontSize', 11);

sgtitle('One-Way User Plane Latency vs Elevation — All SCS', 'FontSize', 14, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase5_latency_vs_elevation.png'));
fprintf('  Saved: phase5_latency_vs_elevation.png\n');

%% =====================================================================
%  SECTION 5: LATENCY COMPARISON — TRANSPARENT vs REGENERATIVE
%  =====================================================================
fprintf('--- Section 5: Direct comparison ---\n');

figure('Name', 'Latency Comparison', 'Position', [100 100 1000 500]);

% Use 15 kHz SCS as primary comparison
scsIdx = 1;  % 15 kHz

subplot(1, 2, 1);
plot(elevSweep, lat_transparent(:, scsIdx), '-ro', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Transparent');
hold on;
plot(elevSweep, lat_regenerative(:, scsIdx), '-bs', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Regenerative');
hold off;
xlabel('Elevation Angle (deg)', 'FontSize', 12);
ylabel('One-Way Latency (ms)', 'FontSize', 12);
title(sprintf('Latency Comparison — SCS 15 kHz'), 'FontSize', 13);
legend('Location', 'northeast', 'FontSize', 10);
grid on; set(gca, 'FontSize', 11);

% Percentage reduction
subplot(1, 2, 2);
pctReduction = 100 * (lat_transparent(:, scsIdx) - lat_regenerative(:, scsIdx)) ...
               ./ lat_transparent(:, scsIdx);
plot(elevSweep, pctReduction, '-g', 'LineWidth', 2, 'MarkerSize', 5);
xlabel('Elevation Angle (deg)', 'FontSize', 12);
ylabel('Latency Reduction (%)', 'FontSize', 12);
title('Regenerative Latency Advantage', 'FontSize', 13);
grid on; set(gca, 'FontSize', 11);
ylim([0 max(pctReduction)*1.2]);

sgtitle('Transparent vs Regenerative Latency — 5G NR LEO NTN', ...
    'FontSize', 14, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase5_latency_comparison.png'));
fprintf('  Saved: phase5_latency_comparison.png\n');

%% =====================================================================
%  SECTION 6: HARQ ROUND-TRIP TIME ANALYSIS
%  =====================================================================
fprintf('\n--- Section 6: HARQ Round-Trip Time Analysis ---\n');

% HARQ RTT = 2 × propagation delay + UE processing + Sat/GW processing + K1 slots
% Transparent: HARQ disabled (RTT >> 8ms standard timer)
% Regenerative: HARQ enabled with extended timer

figure('Name', 'HARQ RTT', 'Position', [100 100 900 500]);

hold on;
for s = 1:nSCS
    slotDur_ms = 1 / (2^(log2(scsValues(s)/15)));
    harqK1_ms  = harq_K1_slots * slotDur_ms;
    
    % Regenerative HARQ RTT (UE → Sat → decode → NACK → UE retx)
    harqRTT_regen = 2 * propDelay_ms + T_UE_proc_ms + T_sat_regen_ms + harqK1_ms;
    
    plot(elevSweep, harqRTT_regen, '-', 'LineWidth', 1.5, 'Color', colors(s,:), ...
        'DisplayName', sprintf('Regen SCS %d kHz', scsValues(s)));
end

% Transparent HARQ RTT (would be if enabled — show as dashed to illustrate why disabled)
harqRTT_transp = 2 * (2 * propDelay_ms) + T_UE_proc_ms + T_GW_proc_ms + harq_K1_slots * 1.0;
plot(elevSweep, harqRTT_transp, '--k', 'LineWidth', 2, ...
    'DisplayName', 'Transparent (disabled)');

% Standard HARQ timer line (8 ms)
yline(8, ':r', 'Standard HARQ Timer (8 ms)', 'LineWidth', 1.5, ...
    'LabelHorizontalAlignment', 'left', 'FontSize', 9);

hold off;
xlabel('Elevation Angle (deg)', 'FontSize', 12);
ylabel('HARQ RTT (ms)', 'FontSize', 12);
title('HARQ Round-Trip Time vs Elevation', 'FontSize', 13);
legend('Location', 'northeast', 'FontSize', 8);
grid on; set(gca, 'FontSize', 11);
saveas(gcf, fullfile(params.outputDir, 'phase5_harq_rtt.png'));
fprintf('  Saved: phase5_harq_rtt.png\n');

fprintf('  HARQ RTT at 50 deg elevation:\n');
for s = 1:nSCS
    slotDur_ms = 1 / (2^(log2(scsValues(s)/15)));
    rtt_regen = 2*propDelay_ms(refElevIdx) + T_UE_proc_ms + T_sat_regen_ms + harq_K1_slots*slotDur_ms;
    fprintf('    SCS %3d kHz (regen) : %.1f ms\n', scsValues(s), rtt_regen);
end
rtt_transp = 2*(2*propDelay_ms(refElevIdx)) + T_UE_proc_ms + T_GW_proc_ms + harq_K1_slots*1.0;
fprintf('    Transparent (if enabled): %.1f ms >> 8 ms standard timer\n', rtt_transp);
fprintf('    → HARQ disabled for transparent per TR 38.821 Sec 7.3\n\n');

%% =====================================================================
%  SECTION 7: LATENCY CDF (Monte Carlo over varying elevations)
%  =====================================================================
fprintf('--- Section 7: Latency CDF (Monte Carlo) ---\n');

% Use Phase 1 elevation time-series for realistic elevation distribution
nMC = 10000;
rng(params.sim.rngSeed);

% Sample random elevations from the Phase 1 elevation distribution
% Use all UEs' elevation data, filter to visible periods only
allElevData = phase1.elevationTimeSeries(:);
visibleElev = allElevData(allElevData > params.ue.minElevation);

if isempty(visibleElev)
    % Fallback: use uniform distribution 10-90 deg
    fprintf('  WARNING: No visible elevations in Phase 1 data. Using uniform 10-90 deg.\n');
    visibleElev = 10 + 80 * rand(10000, 1);
end

% Sample nMC elevations from the empirical distribution
sampledElev = visibleElev(randi(length(visibleElev), nMC, 1));

% Add small random jitter for scheduling and processing
schedJitter_ms = 0.5 * randn(nMC, 1);  % Small timing variations

% Compute latency for each sample (15 kHz SCS)
scs15_sched = nSchedSlots * 1.0;  % ms

latSamples_transp = zeros(nMC, 1);
latSamples_regen  = zeros(nMC, 1);

for i = 1:nMC
    [~, pd] = computeSlantRange(sampledElev(i), params.sat.altitude, params.R_earth, c);
    pd_ms = pd * 1e3;
    jitter = abs(schedJitter_ms(i));  % Positive jitter only
    
    latSamples_transp(i) = T_UE_proc_ms + 2*pd_ms + T_sat_transp_ms + ...
                           T_GW_proc_ms + scs15_sched + jitter;
    latSamples_regen(i)  = T_UE_proc_ms + pd_ms + T_sat_regen_ms + ...
                           scs15_sched + jitter;
end

figure('Name', 'Latency CDF', 'Position', [100 100 900 500]);
[fT, xT] = ecdf(latSamples_transp);
[fR, xR] = ecdf(latSamples_regen);
plot(xT, fT, '-r', 'LineWidth', 2, 'DisplayName', 'Transparent');
hold on;
plot(xR, fR, '-b', 'LineWidth', 2, 'DisplayName', 'Regenerative');

% Mark 50th and 95th percentiles
p50_T = prctile(latSamples_transp, 50);
p95_T = prctile(latSamples_transp, 95);
p50_R = prctile(latSamples_regen, 50);
p95_R = prctile(latSamples_regen, 95);

xline(p50_T, '--r', sprintf('T 50%%=%.1f', p50_T), 'LineWidth', 1, 'FontSize', 8);
xline(p95_T, ':r', sprintf('T 95%%=%.1f', p95_T), 'LineWidth', 1, 'FontSize', 8);
xline(p50_R, '--b', sprintf('R 50%%=%.1f', p50_R), 'LineWidth', 1, 'FontSize', 8);
xline(p95_R, ':b', sprintf('R 95%%=%.1f', p95_R), 'LineWidth', 1, 'FontSize', 8);
hold off;

xlabel('One-Way Latency (ms)', 'FontSize', 12);
ylabel('CDF', 'FontSize', 12);
title('Latency CDF — Monte Carlo (10,000 samples, 15 kHz SCS)', 'FontSize', 13);
legend('Location', 'southeast', 'FontSize', 10);
grid on; set(gca, 'FontSize', 11);
saveas(gcf, fullfile(params.outputDir, 'phase5_latency_cdf.png'));
fprintf('  Saved: phase5_latency_cdf.png\n');

fprintf('  Latency statistics (15 kHz SCS):\n');
fprintf('    Transparent:  median=%.1f ms, 95th=%.1f ms, mean=%.1f ms\n', ...
    p50_T, p95_T, mean(latSamples_transp));
fprintf('    Regenerative: median=%.1f ms, 95th=%.1f ms, mean=%.1f ms\n', ...
    p50_R, p95_R, mean(latSamples_regen));
fprintf('    Median reduction: %.1f ms (%.0f%%)\n\n', ...
    p50_T - p50_R, 100*(p50_T - p50_R)/p50_T);

%% =====================================================================
%  SECTION 8: VALIDATION CHECKS
%  =====================================================================
fprintf('--- Section 8: Validation checks ---\n');

fprintf('  [CHECK] Transparent latency > Regenerative at all elevations... ');
if all(lat_transparent(:,1) > lat_regenerative(:,1)), fprintf('PASS\n'); else, fprintf('FAIL\n'); end

fprintf('  [CHECK] Propagation delay at 10 deg ~6.4 ms... ');
if abs(propDelay_ms(1) - 6.4) < 0.5, fprintf('PASS (%.2f ms)\n', propDelay_ms(1)); 
else, fprintf('WARNING (%.2f ms)\n', propDelay_ms(1)); end

fprintf('  [CHECK] Propagation delay at 90 deg ~2.0 ms... ');
if abs(propDelay_ms(end) - 2.0) < 0.5, fprintf('PASS (%.2f ms)\n', propDelay_ms(end)); 
else, fprintf('WARNING (%.2f ms)\n', propDelay_ms(end)); end

latReduction = mean(pctReduction);
fprintf('  [CHECK] Mean latency reduction = %.0f%% (expected 25-50%%)... ', latReduction);
if latReduction > 15 && latReduction < 60, fprintf('PASS\n'); else, fprintf('WARNING\n'); end

fprintf('  [CHECK] Transparent HARQ RTT >> 8 ms... ');
if rtt_transp > 15, fprintf('PASS (%.1f ms)\n', rtt_transp); else, fprintf('WARNING\n'); end

fprintf('\n');

%% =====================================================================
%  SECTION 9: EXPORT RESULTS
%  =====================================================================
fprintf('--- Section 9: Exporting results ---\n');

phase5 = struct();

% Elevation sweep data
phase5.elevSweep          = elevSweep;
phase5.propDelay_ms       = propDelay_ms;
phase5.scsValues          = scsValues;

% Latency matrices [nElev x nSCS]
phase5.lat_transparent    = lat_transparent;
phase5.lat_regenerative   = lat_regenerative;

% Component breakdown at reference elevation
phase5.refElev            = refElev;
phase5.comp_transp        = comp_transp;
phase5.comp_regen         = comp_regen;
phase5.compLabels         = compLabels;

% Fixed delays
phase5.T_UE_proc_ms      = T_UE_proc_ms;
phase5.T_GW_proc_ms      = T_GW_proc_ms;
phase5.T_sat_transp_ms   = T_sat_transp_ms;
phase5.T_sat_regen_ms    = T_sat_regen_ms;
phase5.nSchedSlots        = nSchedSlots;

% HARQ
phase5.harq_K1_slots      = harq_K1_slots;
phase5.harq_nMaxReTx      = harq_nMaxReTx;

% CDF statistics
phase5.latCDF_transp_median = p50_T;
phase5.latCDF_transp_95     = p95_T;
phase5.latCDF_regen_median  = p50_R;
phase5.latCDF_regen_95      = p95_R;

outFile = fullfile(params.outputDir, 'phase5_results.mat');
save(outFile, 'phase5', '-v7.3');
fprintf('  Saved: %s\n', outFile);

%% =====================================================================
%  SUMMARY
%  =====================================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 5 COMPLETE\n');
fprintf('============================================================\n');
fprintf('  Latency computed for %d elevations x %d SCS values\n', nElev, nSCS);
fprintf('  At %d deg elevation (15 kHz SCS):\n', refElev);
fprintf('    Transparent : %.1f ms\n', sum(comp_transp));
fprintf('    Regenerative: %.1f ms\n', sum(comp_regen));
fprintf('    Reduction   : %.1f ms (%.0f%%)\n', ...
    sum(comp_transp)-sum(comp_regen), ...
    100*(sum(comp_transp)-sum(comp_regen))/sum(comp_transp));
fprintf('  HARQ: Disabled for transparent, enabled for regenerative\n');
fprintf('  Monte Carlo CDF: %d samples from Phase 1 elevation data\n', nMC);
fprintf('\n  Load in Phase 6: load(''results/phase5_results.mat'')\n');
fprintf('============================================================\n');
