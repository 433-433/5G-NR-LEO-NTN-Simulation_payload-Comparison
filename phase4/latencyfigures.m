%% ========================================================================
%  LATENCY FIGURES for the camera-ready paper
%  ========================================================================
%  Produces the three "latency" figures with the reviewer corrections:
%    - fig_latency_breakdown.png : stacked bars at 50° elevation showing
%                                   T_UE, T_prop, T_sat, T_GW-core, T_sched
%                                   for both payloads, with the Sat→GW
%                                   feeder hop now visible in the regen bar
%    - fig_latency_comparison.png : line comparison 10°–90° (right panel
%                                   extends past 55° to show the crossover)
%
%  Self-contained — needs no prior .mat; computes slant range analytically.
%  Writes to results/camera_ready/ with the filenames the .tex expects.
%
%  Also prints the per-elevation numbers so you can cross-check them in
%  Section VI of the paper.
%  ========================================================================
clc; clear; close all;

outDir = fullfile(pwd,'results','camera_ready');
if ~exist(outDir,'dir'); mkdir(outDir); end

c      = physconst('lightspeed');
R_e    = 6371e3;
h      = 600e3;
elev   = 10:1:90;

alpha  = deg2rad(elev);
slant  = sqrt((h+R_e)^2 - (R_e*cos(alpha)).^2) - R_e*sin(alpha);
Tp_sat_ue = slant / c;              % one-way service-link prop (s)

% Fixed latency components (paper Section VI)
T_UE        = 1.0e-3;
T_sat_t     = 0.1e-3;               % transparent on-board forwarding
T_sat_r     = 4.0e-3;               % regenerative on-board processing
T_GW_core   = 1.5e-3;               % gateway + core transit
T_sched_15  = 4e-3;                 % 4 slots at 15 kHz SCS
Tp_sat_gw   = 2.0e-3;               % nominal sat-to-gateway slant (nadir baseline)

% Totals per payload
L_transp = T_UE + 2*Tp_sat_ue + T_sat_t + T_GW_core + T_sched_15;    % s
L_regen  = T_UE +   Tp_sat_ue + T_sat_r + Tp_sat_gw + T_GW_core + T_sched_15;

%% ------------------------------------------------------------------
%% FIG 1 : Component breakdown at the 50° reference elevation
%% ------------------------------------------------------------------
k50     = find(elev == 50);
Tp_50_t = Tp_sat_ue(k50);           % transparent uses service link twice
Tp_50_r = Tp_sat_ue(k50);           % regen uses it once

%          UE    prop(ue-sat)   sat     feeder/GW-core        sched
bars_t = [T_UE   2*Tp_50_t      T_sat_t 0+T_GW_core           T_sched_15];
bars_r = [T_UE     Tp_50_r      T_sat_r Tp_sat_gw+T_GW_core   T_sched_15];
labels = {'UE processing','Service-link propagation','On-board processing','Feeder + core transit','Scheduling'};

f1 = figure('Position',[80 80 950 460],'Color','w');
hb = bar([bars_t; bars_r]*1e3, 'stacked');
cols = [0.4 0.6 0.9;  0.95 0.6 0.3;  0.65 0.4 0.75;  0.4 0.75 0.5;  0.80 0.80 0.35];
for i=1:5; hb(i).FaceColor = cols(i,:); end
set(gca,'XTickLabel',{'Transparent','Regenerative'}, 'FontSize',12);
ylabel('One-way latency (ms)','FontSize',12);
title(sprintf('Latency breakdown at 50° elevation, 15 kHz SCS  (total: T=%.2f ms  R=%.2f ms)', ...
    sum(bars_t)*1e3, sum(bars_r)*1e3),'FontSize',12);
legend(labels,'Location','eastoutside','FontSize',10);
grid on; set(gca,'FontSize',11);
saveas(f1, fullfile(outDir,'fig_latency_breakdown.png'));
fprintf('Saved fig_latency_breakdown.png\n');

%% ------------------------------------------------------------------
%% FIG 2 : Full elevation sweep + percentage reduction (extended past 55°)
%% ------------------------------------------------------------------
f2 = figure('Position',[80 80 1100 450],'Color','w');

% Left: absolute latency vs elevation
subplot(1,2,1); hold on; grid on;
plot(elev, L_transp*1e3, '-s','LineWidth',2,'MarkerSize',5, ...
     'Color',[0.85 0.33 0.10],'MarkerFaceColor',[0.85 0.33 0.10], ...
     'DisplayName','Transparent');
plot(elev, L_regen*1e3,  '-o','LineWidth',2,'MarkerSize',5, ...
     'Color',[0.00 0.45 0.74],'MarkerFaceColor',[0.00 0.45 0.74], ...
     'DisplayName','Regenerative');
xlabel('Elevation (°)','FontSize',12); ylabel('One-way latency (ms)','FontSize',12);
title('End-to-end latency vs elevation','FontSize',12);
legend('Location','northeast','FontSize',10); set(gca,'FontSize',11);
xlim([10 90]);

% Right: % reduction, with the crossover visible (not truncated at 55°)
subplot(1,2,2); hold on; grid on;
reduction = (L_transp - L_regen) ./ L_transp * 100;
plot(elev, reduction, '-^','LineWidth',2.2,'MarkerSize',5, ...
     'Color',[0.20 0.60 0.30],'MarkerFaceColor',[0.20 0.60 0.30], ...
     'DisplayName','Regen advantage (%)');
yline(0, '--k', 'Crossover','LineWidth',1,'LabelHorizontalAlignment','right');
xlabel('Elevation (°)','FontSize',12); ylabel('Latency reduction (%)','FontSize',12);
title('Regenerative latency advantage (extended past 55°)','FontSize',12);
% Annotate the crossover elevation
cross_idx = find(reduction <= 0, 1, 'first');
if ~isempty(cross_idx)
    cross_el = elev(cross_idx);
    text(cross_el+1, 1, sprintf('crossover at %d°', cross_el), ...
         'FontSize',10,'FontWeight','bold');
end
set(gca,'FontSize',11); xlim([10 90]);

sgtitle('Transparent vs regenerative latency — end-to-end with feeder hop', ...
        'FontWeight','bold','FontSize',13);
saveas(f2, fullfile(outDir,'fig_latency_comparison.png'));
fprintf('Saved fig_latency_comparison.png\n');

%% Numbers for cross-check with the paper
fprintf('\nLatency per elevation (ms):\n');
fprintf('  Elev  Transp   Regen   Reduction\n');
for e_target = [10 20 30 50 70 90]
    ke = find(elev == e_target);
    fprintf('  %3d°  %6.2f   %6.2f  %6.1f %%\n', ...
        e_target, L_transp(ke)*1e3, L_regen(ke)*1e3, reduction(ke));
end
if ~isempty(cross_idx)
    fprintf('\n  Crossover elevation (regen = transp): %d°\n', elev(cross_idx));
end