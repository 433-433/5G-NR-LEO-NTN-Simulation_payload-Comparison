%% ========================================================================
%  PHASE 1 FIGURES for the camera-ready paper
%  ========================================================================
%  Produces the two "new" figures the reviewer asked for:
%    - fig_ghana_coverage.png       : map of Ghana with gateways, UEs,
%                                     and 24h visibility stats
%    - fig_elev_latency_cdf.png     : elevation CDF + latency CDF
%
%  Reads results/phase1_results.mat (your existing Phase 1 output) and
%  writes to results/camera_ready/ with the filenames the .tex expects.
%
%  Needs no external map data — Ghana borders are drawn from an inline
%  polygon that's accurate enough for a conference figure. If you prefer a
%  proper basemap, swap the border polygon for a geoplot/geoshape call.
%  ========================================================================
clc; clear; close all;
addpath('config');
params = systemParams();

inFile  = fullfile(params.outputDir, 'phase1_results.mat');
outDir  = fullfile(params.outputDir, 'camera_ready');
if ~exist(outDir,'dir'); mkdir(outDir); end
load(inFile,'phase1');

% ---- colours ----
C_gw = [0.70 0.15 0.15];      % red triangle
C_ue = [0.00 0.45 0.74];      % blue dot
C_box = [0.85 0.85 0.85];

%% ------------------------------------------------------------------
%% FIGURE 1 : Ghana coverage map
%% ------------------------------------------------------------------
f1 = figure('Position',[80 80 900 700],'Color','w'); hold on;

% Simple Ghana border polygon (approximate, 20 vertices).
% For a camera-ready figure this is clean enough; swap in a shapefile
% if you want a true border.
borderLon = [-3.26 -2.94 -2.75 -2.53 -2.40 -1.96 -1.07 -0.47 -0.07 ...
              0.08  0.34  0.72  1.19  1.00  0.63 -0.14 -0.72 -2.70 -3.11 -3.26];
borderLat = [ 5.00  5.11  5.20  4.74  4.89  5.08  5.11  5.20  5.68 ...
              6.20  6.45  7.45  9.21 10.21 10.95 11.14 11.00 11.00  9.49  5.00];
patch(borderLon, borderLat, [0.96 0.98 0.96], 'EdgeColor',[0.4 0.5 0.4], 'LineWidth',1.2);

% Gateways
for i = 1:phase1.params.gw.count
    plot(phase1.params.gw.lon(i), phase1.params.gw.lat(i), 'v', ...
         'MarkerSize',14,'MarkerFaceColor',C_gw,'MarkerEdgeColor','k','LineWidth',1);
    text(phase1.params.gw.lon(i)+0.08, phase1.params.gw.lat(i)+0.08, ...
         strrep(phase1.params.gw.names(i),'GW_',''), ...
         'FontSize',9,'FontWeight','bold','Color',C_gw);
end

% UEs
for i = 1:phase1.params.ue.count
    plot(phase1.params.ue.lon(i), phase1.params.ue.lat(i), 'o', ...
         'MarkerSize',6,'MarkerFaceColor',C_ue,'MarkerEdgeColor','k');
end

% Visibility stats as inset
annoText = sprintf('Walker 72/6/1 @ 600 km\\n%d gateways, %d UEs\\nMean visibility: %.1f%%\\nMean handovers/hr: %.1f', ...
    phase1.params.gw.count, phase1.params.ue.count, ...
    mean(phase1.visibilityPct), mean(phase1.handoverRate));
text(-3.1, 10.6, sprintf('%s', annoText), ...
     'FontSize',10,'EdgeColor',[0.4 0.4 0.4],'BackgroundColor',[1 1 1 0.9], ...
     'Margin',6,'FontName','Helvetica');

xlabel('Longitude (°E)','FontSize',12);
ylabel('Latitude (°N)','FontSize',12);
title('Ghana reference scenario — 8 gateways, 16 UEs, Walker-72 visibility','FontSize',13);
axis equal; grid on; set(gca,'FontSize',11,'GridColor',[0.9 0.9 0.9]);
xlim([-3.6 1.4]); ylim([4.5 11.5]);

% Legend proxies
hGW = plot(NaN,NaN,'v','MarkerSize',12,'MarkerFaceColor',C_gw,'MarkerEdgeColor','k');
hUE = plot(NaN,NaN,'o','MarkerSize',8,'MarkerFaceColor',C_ue,'MarkerEdgeColor','k');
legend([hGW hUE],{'Gateway (43 dBi dish)','UE (0 dBi, handheld)'}, ...
       'Location','southeast','FontSize',10);

saveas(f1, fullfile(outDir,'fig_ghana_coverage.png'));
fprintf('Saved fig_ghana_coverage.png\n');

%% ------------------------------------------------------------------
%% FIGURE 2 : Elevation CDF + Latency CDF
%% ------------------------------------------------------------------
% Elevation samples: all points where a satellite is visible (> minElev)
elev = phase1.elevationTimeSeries(:);
elev = elev(elev > 0 & isfinite(elev));

% Latency computed from elevation via corrected one-way expressions
c = physconst('lightspeed');
R_e = 6371e3; h = 600e3;

% slant range per elevation value
alpha = deg2rad(elev);
slant = sqrt((h+R_e)^2 - (R_e*cos(alpha)).^2) - R_e*sin(alpha);
Tprop_sat_ue = slant / c;                % s

% Reference parameters (match the paper)
T_UE        = 1.0e-3;
T_sat_t     = 0.1e-3;
T_sat_r     = 4.0e-3;
T_GW_core   = 1.5e-3;
T_sched_15  = 4 * 1e-3 / 2^0;            % 4 ms at 15 kHz SCS
Tprop_sat_gw = 2.0e-3;                   % typical sat-GW slant (nominal)

L_transp = T_UE + 2*Tprop_sat_ue + T_sat_t + T_GW_core + T_sched_15;
L_regen  = T_UE +   Tprop_sat_ue + T_sat_r + Tprop_sat_gw + T_GW_core + T_sched_15;

f2 = figure('Position',[80 80 1100 450],'Color','w');

% ---- Left: elevation CDF ----
subplot(1,2,1); hold on; grid on;
[fE, xE] = ecdf(elev);
plot(xE, fE, 'LineWidth',2, 'Color',[0 0.45 0.74]);
yline(0.5,':k','50%','LineWidth',1,'HandleVisibility','off');
yline(0.9,':k','90%','LineWidth',1,'HandleVisibility','off');
med = median(elev); p90 = prctile(elev,90);
xline(med,'--','Color',[0 0.45 0.74],'HandleVisibility','off');
xline(p90,'--','Color',[0 0.45 0.74],'HandleVisibility','off');
text(med+1, 0.1, sprintf('median %.1f°',med), 'FontSize',9,'Color',[0 0.45 0.74]);
text(p90+1, 0.95,sprintf('90%%ile %.1f°',p90),'FontSize',9,'Color',[0 0.45 0.74]);
xlabel('Elevation (°)','FontSize',12); ylabel('CDF','FontSize',12);
title('Elevation CDF — 24 h over Ghana','FontSize',12);
xlim([0 90]); ylim([0 1]); set(gca,'FontSize',11);

% ---- Right: latency CDF (both payloads) ----
subplot(1,2,2); hold on; grid on;
[fT, xT] = ecdf(L_transp*1e3);
[fR, xR] = ecdf(L_regen*1e3);
plot(xR, fR, 'LineWidth',2, 'Color',[0.00 0.45 0.74],'DisplayName','Regenerative');
plot(xT, fT, 'LineWidth',2, 'Color',[0.85 0.33 0.10],'DisplayName','Transparent');
yline(0.5,':k','50%','LineWidth',1,'HandleVisibility','off');
yline(0.95,':k','95%','LineWidth',1,'HandleVisibility','off');
xlabel('One-way latency (ms)','FontSize',12); ylabel('CDF','FontSize',12);
title('Latency CDF — 15 kHz SCS, incl. feeder hop','FontSize',12);
legend('Location','southeast','FontSize',10); set(gca,'FontSize',11);
ylim([0 1]);

sgtitle('Elevation and latency distributions — 24 h, 16 UEs, Walker 72/6/1', ...
        'FontWeight','bold','FontSize',13);
saveas(f2, fullfile(outDir,'fig_elev_latency_cdf.png'));
fprintf('Saved fig_elev_latency_cdf.png\n');

%% Reported numbers (append to the paper)
fprintf('\nFor the paper:\n');
fprintf('  Elevation median = %.1f°, 90th percentile = %.1f°\n', med, p90);
fprintf('  Regen latency: median %.2f ms, 95th %.2f ms\n', ...
    median(L_regen)*1e3, prctile(L_regen,95)*1e3);
fprintf('  Transp latency: median %.2f ms, 95th %.2f ms\n', ...
    median(L_transp)*1e3, prctile(L_transp,95)*1e3);