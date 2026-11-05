%% ========================================================================
%  PHASE 6B: Additional Throughput Comparison Figures
%  ========================================================================
%  This script loads Phase 6 results and generates EXTRA comparison plots.
%  It does NOT replace Phase 6 — run it after phase6_throughput completes.
%
%  New figures:
%    1. Combined throughput (both payloads on same plot, per SCS)
%    2. Multi-SNR bar chart showing transition region
%    3. Throughput gain (Mbps difference) vs SNR
%    4. Throughput at link-budget operating point per elevation
%  ========================================================================
clc; clear; close all;

addpath('config');
addpath('helpers');
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 6B: Additional Throughput Comparison Figures\n');
fprintf('============================================================\n\n');

load(fullfile(params.outputDir, 'phase6_results.mat'), 'phase6');
load(fullfile(params.outputDir, 'phase4_results.mat'), 'phase4');
fprintf('  Phase 6 and Phase 4 loaded.\n\n');

scsValues  = phase6.scsValues;
rbCounts   = phase6.rbCounts;
snrRange   = phase6.snrRange_dB;
tput_regen = phase6.tput_regen;
tput_transp = phase6.tput_transp;
maxTput    = phase6.maxTput;
nSCS       = length(scsValues);
snrDeg     = phase4.snrDegradation;

colors = lines(nSCS);

%% ---- Figure 1: COMBINED — Both payloads on same plot per SCS ----
fprintf('--- Figure 1: Combined throughput curves ---\n');

figure('Name', 'Combined Throughput', 'Position', [100 100 1100 700]);

for s = 1:nSCS
    subplot(2, 2, s);
    plot(snrRange, tput_regen(:, s), '-bs', 'LineWidth', 2, 'MarkerSize', 5, ...
        'DisplayName', 'Regenerative');
    hold on;
    plot(snrRange, tput_transp(:, s), '-ro', 'LineWidth', 2, 'MarkerSize', 5, ...
        'DisplayName', 'Transparent');
    
    % Mark the 3.4 dB shift with an arrow annotation
    % Find 50% throughput points
    halfTput = maxTput(s) * 0.5;
    idxR = find(tput_regen(:,s) >= halfTput, 1, 'first');
    idxT = find(tput_transp(:,s) >= halfTput, 1, 'first');
    if ~isempty(idxR) && ~isempty(idxT)
        xline(snrRange(idxR), ':b', 'LineWidth', 1, 'HandleVisibility', 'off');
        xline(snrRange(idxT), ':r', 'LineWidth', 1, 'HandleVisibility', 'off');
        % Label the gap
        midY = halfTput;
        midX = (snrRange(idxR) + snrRange(idxT)) / 2;
        text(midX, midY * 0.6, sprintf('%.1f dB\ngain', snrRange(idxT)-snrRange(idxR)), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', ...
            'Color', [0 0.5 0]);
    end
    
    hold off;
    xlabel('SNR (dB)', 'FontSize', 10);
    ylabel('Throughput (Mbps)', 'FontSize', 10);
    title(sprintf('SCS %d kHz (%d RBs)', scsValues(s), rbCounts(s)), 'FontSize', 11);
    legend('Location', 'northwest', 'FontSize', 8);
    grid on; set(gca, 'FontSize', 9);
    ylim([0 maxTput(s) * 1.15]);
end

sgtitle(sprintf('PDSCH Throughput — Regenerative vs Transparent (NTN-TDL-C, 16QAM R=0.48, %.1f dB penalty)', snrDeg), ...
    'FontSize', 12, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase6b_combined_throughput.png'));
fprintf('  Saved: phase6b_combined_throughput.png\n');

%% ---- Figure 2: Multi-SNR Bar Chart (Transition Region) ----
fprintf('--- Figure 2: Multi-SNR bar chart ---\n');

% Show bars at 4, 5, 6, 7, 8 dB — the transition region
barSNRs = [4, 5, 6, 7, 8];
nBarSNR = length(barSNRs);

figure('Name', 'Multi-SNR Bars', 'Position', [100 100 1200 500]);

for s = 1:nSCS
    subplot(1, nSCS, s);
    
    tputR = zeros(nBarSNR, 1);
    tputT = zeros(nBarSNR, 1);
    
    for b = 1:nBarSNR
        [~, idx] = min(abs(snrRange - barSNRs(b)));
        tputR(b) = tput_regen(idx, s);
        tputT(b) = tput_transp(idx, s);
    end
    
    barData = [tputT, tputR];
    bh = bar(barData, 'grouped');
    bh(1).FaceColor = [0.85 0.33 0.1];  % Transparent
    bh(2).FaceColor = [0.0 0.45 0.74];  % Regenerative
    
    set(gca, 'XTickLabel', arrayfun(@(x) sprintf('%d dB', x), barSNRs, 'UniformOutput', false));
    xlabel('SNR', 'FontSize', 10);
    ylabel('Throughput (Mbps)', 'FontSize', 10);
    title(sprintf('SCS %d kHz', scsValues(s)), 'FontSize', 11);
    
    if s == 1
        legend({'Transparent', 'Regenerative'}, 'Location', 'northwest', 'FontSize', 7);
    end
    
    grid on; set(gca, 'FontSize', 8);
    ylim([0 maxTput(s) * 1.15]);
    
    % Add value labels
    for b = 1:nBarSNR
        if tputT(b) > 0
            text(b - 0.15, tputT(b) + maxTput(s)*0.02, sprintf('%.0f', tputT(b)), ...
                'HorizontalAlignment', 'center', 'FontSize', 6, 'FontWeight', 'bold');
        end
        if tputR(b) > 0
            text(b + 0.15, tputR(b) + maxTput(s)*0.02, sprintf('%.0f', tputR(b)), ...
                'HorizontalAlignment', 'center', 'FontSize', 6, 'FontWeight', 'bold', 'Color', 'b');
        end
    end
end

sgtitle('Throughput in Transition Region (SNR 4–8 dB) — Where Payloads Differ', ...
    'FontSize', 12, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase6b_transition_bars.png'));
fprintf('  Saved: phase6b_transition_bars.png\n');

%% ---- Figure 3: Throughput Gain vs SNR ----
fprintf('--- Figure 3: Throughput gain ---\n');

figure('Name', 'Throughput Gain', 'Position', [100 100 900 550]);

subplot(2, 1, 1);
hold on;
for s = 1:nSCS
    gain = tput_regen(:, s) - tput_transp(:, s);
    plot(snrRange, gain, '-o', 'LineWidth', 2, 'MarkerSize', 4, ...
        'Color', colors(s,:), ...
        'DisplayName', sprintf('SCS %d kHz', scsValues(s)));
end
hold off;
xlabel('SNR (dB)', 'FontSize', 11);
ylabel('Throughput Gain (Mbps)', 'FontSize', 11);
title('Regenerative Throughput Advantage Over Transparent', 'FontSize', 12);
legend('Location', 'northeast', 'FontSize', 8);
grid on; set(gca, 'FontSize', 10);

subplot(2, 1, 2);
hold on;
for s = 1:nSCS
    pctGain = 100 * (tput_regen(:,s) - tput_transp(:,s)) ./ max(tput_regen(:,s), 0.01);
    pctGain(tput_regen(:,s) == 0) = 0;  % Avoid division artifacts
    plot(snrRange, pctGain, '-s', 'LineWidth', 2, 'MarkerSize', 4, ...
        'Color', colors(s,:), ...
        'DisplayName', sprintf('SCS %d kHz', scsValues(s)));
end
hold off;
xlabel('SNR (dB)', 'FontSize', 11);
ylabel('Throughput Gain (%)', 'FontSize', 11);
title('Percentage Throughput Gain of Regenerative', 'FontSize', 12);
legend('Location', 'northeast', 'FontSize', 8);
grid on; set(gca, 'FontSize', 10);
ylim([0 110]);

sgtitle('Regenerative vs Transparent — Throughput Gain Analysis', ...
    'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase6b_throughput_gain.png'));
fprintf('  Saved: phase6b_throughput_gain.png\n');

%% ---- Figure 4: Throughput at Link Budget Operating Points ----
fprintf('--- Figure 4: Throughput at link budget operating points ---\n');

% Use Phase 4 link budget SNR per elevation
elevBudget    = phase4.elevBudget;
snr_regen_elev = phase4.snr_regen;      % SNR at each elevation (regenerative)
snr_transp_elev = phase4.snr_cascaded;   % SNR at each elevation (transparent)
nElev = length(elevBudget);

% Interpolate throughput at each elevation's actual SNR
% Use SCS = 15 kHz (index 1) as primary
tput_at_elev_R = zeros(nElev, 1);
tput_at_elev_T = zeros(nElev, 1);

for e = 1:nElev
    % Regenerative: look up throughput at regen SNR
    tput_at_elev_R(e) = interp1(snrRange, tput_regen(:,1), snr_regen_elev(e), 'linear', 0);
    % Transparent: look up throughput at transparent SNR
    tput_at_elev_T(e) = interp1(snrRange, tput_transp(:,1), snr_transp_elev(e), 'linear', 0);
    
    % Clamp to valid range
    tput_at_elev_R(e) = max(0, min(tput_at_elev_R(e), maxTput(1)));
    tput_at_elev_T(e) = max(0, min(tput_at_elev_T(e), maxTput(1)));
end

figure('Name', 'Tput vs Elevation', 'Position', [100 100 900 500]);

subplot(1, 2, 1);
x = 1:nElev;
barWidth = 0.35;
bar(x - barWidth/2, tput_at_elev_T, barWidth, 'FaceColor', [0.85 0.33 0.1]);
hold on;
bar(x + barWidth/2, tput_at_elev_R, barWidth, 'FaceColor', [0.0 0.45 0.74]);
hold off;
set(gca, 'XTick', x, 'XTickLabel', arrayfun(@(e) sprintf('%d°', e), elevBudget, 'UniformOutput', false));
xlabel('Elevation Angle', 'FontSize', 11);
ylabel('Throughput (Mbps)', 'FontSize', 11);
title('Achievable Throughput per Elevation (15 kHz SCS)', 'FontSize', 12);
legend({'Transparent', 'Regenerative'}, 'Location', 'northwest', 'FontSize', 9);
grid on; set(gca, 'FontSize', 10);

subplot(1, 2, 2);
gain_elev = tput_at_elev_R - tput_at_elev_T;
bar(elevBudget, gain_elev, 0.5, 'FaceColor', [0.2 0.6 0.4]);
hold on;
for e = 1:nElev
    if gain_elev(e) > 0
        text(elevBudget(e), gain_elev(e) + 0.3, sprintf('%.1f', gain_elev(e)), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
    end
end
hold off;
xlabel('Elevation Angle (deg)', 'FontSize', 11);
ylabel('Throughput Gain (Mbps)', 'FontSize', 11);
title('Regenerative Throughput Advantage vs Elevation', 'FontSize', 12);
grid on; set(gca, 'FontSize', 10);

sgtitle('Throughput at Actual Link Budget Operating Points', ...
    'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase6b_throughput_vs_elevation.png'));
fprintf('  Saved: phase6b_throughput_vs_elevation.png\n');

%% ---- Figure 5: Single Combined Overview ----
fprintf('--- Figure 5: Publication overview figure ---\n');

figure('Name', 'Overview', 'Position', [100 100 1200 500]);

% Left: throughput vs SNR (15 kHz SCS, both payloads)
subplot(1, 3, 1);
plot(snrRange, tput_regen(:,1), '-bs', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Regenerative');
hold on;
plot(snrRange, tput_transp(:,1), '-ro', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Transparent');
hold off;
xlabel('SNR (dB)', 'FontSize', 11);
ylabel('Throughput (Mbps)', 'FontSize', 11);
title('SCS 15 kHz — Waterfall', 'FontSize', 12);
legend('Location', 'northwest', 'FontSize', 8);
grid on; set(gca, 'FontSize', 10);

% Middle: bar chart at SNR 6 dB
subplot(1, 3, 2);
barSNR6 = zeros(nSCS, 2);
[~, idx6] = min(abs(snrRange - 6));
for s = 1:nSCS
    barSNR6(s, 1) = tput_transp(idx6, s);
    barSNR6(s, 2) = tput_regen(idx6, s);
end
bh = bar(barSNR6, 'grouped');
bh(1).FaceColor = [0.85 0.33 0.1];
bh(2).FaceColor = [0.0 0.45 0.74];
set(gca, 'XTickLabel', {'15', '30', '60', '120'});
xlabel('SCS (kHz)', 'FontSize', 11);
ylabel('Throughput (Mbps)', 'FontSize', 11);
title('At SNR = 6 dB', 'FontSize', 12);
legend({'Transparent', 'Regenerative'}, 'Location', 'northwest', 'FontSize', 7);
grid on; set(gca, 'FontSize', 10);

% Right: throughput at actual elevation operating points
subplot(1, 3, 3);
bar(x - barWidth/2, tput_at_elev_T, barWidth, 'FaceColor', [0.85 0.33 0.1]);
hold on;
bar(x + barWidth/2, tput_at_elev_R, barWidth, 'FaceColor', [0.0 0.45 0.74]);
hold off;
set(gca, 'XTick', x, 'XTickLabel', arrayfun(@(e) sprintf('%d°', e), elevBudget, 'UniformOutput', false));
xlabel('Elevation', 'FontSize', 11);
ylabel('Throughput (Mbps)', 'FontSize', 11);
title('At Link Budget SNR', 'FontSize', 12);
legend({'Transp', 'Regen'}, 'Location', 'northwest', 'FontSize', 7);
grid on; set(gca, 'FontSize', 10);

sgtitle('5G NR LEO NTN — Throughput: Regenerative vs Transparent', ...
    'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase6b_publication_overview.png'));
fprintf('  Saved: phase6b_publication_overview.png\n');

%% SUMMARY
fprintf('\n============================================================\n');
fprintf('  PHASE 6B COMPLETE\n');
fprintf('============================================================\n');
fprintf('  5 additional comparison figures generated.\n');
fprintf('  Key insight: At SNR=6 dB, regenerative achieves full\n');
fprintf('  throughput while transparent gets 0 Mbps across all SCS.\n');
fprintf('  The %.1f dB penalty makes transparent non-functional\n', snrDeg);
fprintf('  in the critical 4-8 dB transition region.\n');
fprintf('============================================================\n');
