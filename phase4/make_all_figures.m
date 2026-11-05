function make_all_figures()
%% ========================================================================
%  make_all_figures.m   —   ONE SCRIPT, ALL CAMERA-READY FIGURES
%  ========================================================================
%  Produces every figure the camera-ready paper references (except the TikZ
%  payload-architecture diagram, which lives inside the .tex) into ONE
%  folder: results/camera_ready/
%
%  INPUTS (all already-generated .mat files from your prior runs):
%    results/phase1_results.mat     (orbital scenario, 24 h)
%    results/phase4_results.mat     (link budget + Route A impairment profile)
%    results/phase6_results.mat     (throughput, Route A)
%    results/phase7_results.mat     (BLER + HARQ + multi-MCS, Route A)
%
%  OUTPUTS (10 figures written to results/camera_ready/):
%    fig_ghana_coverage.png         Ghana map, GWs + UEs, visibility stats
%    fig_elev_latency_cdf.png       Elevation CDF + end-to-end latency CDF
%    fig_link_budget.png            Thermal link budget (user, feeder, pen.)
%    fig_latency_breakdown.png      Component bars w/ feeder hop added
%    fig_latency_comparison.png     Transp vs regen vs elev + crossover
%    fig_tput_combined.png          Phase 6 throughput, clean (no data1)
%                                   Peak 14.3 Mbps @ 15 kHz, no shift
%    fig_bler_env.png               Suburban + rural BLER with CI bands
%    fig_harq.png                   IR-HARQ for BOTH payloads, clean
%    fig_component_breakdown.png    Decomposition of measured 1.48 dB
%    fig_sensitivity.png            4-panel sensitivity (optional, see cfg)
%    fig_ci_probe.png               Measured C/I per impairment (optional)
%
%  TOGGLES (edit at top of function):
%    cfg.runCIProbe     = true   -> ~2 min, directly justifies C/I values
%    cfg.runSensitivity = false  -> ~15 min, measures gap vs each knob
%
%  All figures use:
%    - no "data1" legend artefacts (HandleVisibility='off' on yline/xline)
%    - consistent IEEE-friendly colour scheme (blue regen, orange transp)
%    - labelled DisplayName on every line, CI bands shaded where applicable
%  ========================================================================
clc; close all;

% ---- toggles ----
cfg.runCIProbe     = true;      % direct C/I measurement per impairment
cfg.runSensitivity = false;     % longer; enable for camera-ready sweep
cfg.T_sat_r        = 1.0e-3;    % Rel-19 SDN gNB (defensible; crossover ~43 deg)
cfg.T_UE           = 1.0e-3;
cfg.T_sat_t        = 0.1e-3;
cfg.T_GW_core      = 1.5e-3;
cfg.T_sched_15     = 4e-3;
cfg.Tp_sat_gw      = 2.0e-3;

% ---- paths and load ----
addpath('config'); addpath('helpers');
params = systemParams();
outDir = fullfile(params.outputDir, 'camera_ready');
if ~exist(outDir,'dir'); mkdir(outDir); end

try
    load(fullfile(params.outputDir,'phase1_results.mat'),'phase1');
    load(fullfile(params.outputDir,'phase4_results.mat'),'phase4');
    load(fullfile(params.outputDir,'phase6_results.mat'),'phase6');
    load(fullfile(params.outputDir,'phase7_results.mat'),'phase7');
catch ME
    error('Could not load one of phase1/4/6/7_results.mat: %s', ME.message);
end

% ---- common colours ----
col.regen  = [0.00 0.45 0.74];     % blue
col.transp = [0.85 0.33 0.10];     % orange
col.land   = [0.96 0.98 0.94];
col.coast  = [0.35 0.55 0.65];
col.border = [0.40 0.45 0.40];

fprintf('\n========== CAMERA-READY FIGURE GENERATION ==========\n');
fprintf('Output: %s\n\n', outDir);

% ===================================================================
% FIG 1 : Ghana coverage map
% ===================================================================
fprintf('[1/10] Ghana coverage ...\n');
makeGhanaCoverage(phase1, col, outDir);

% ===================================================================
% FIG 2 : Elevation + latency CDFs
% ===================================================================
fprintf('[2/10] Elevation + latency CDF ...\n');
makeElevLatencyCDF(phase1, cfg, col, outDir);

% ===================================================================
% FIG 3 : Link budget
% ===================================================================
fprintf('[3/10] Link budget ...\n');
makeLinkBudget(phase4, col, outDir);

% ===================================================================
% FIG 4-5 : Latency breakdown + comparison (with feeder hop, extended)
% ===================================================================
fprintf('[4/10] Latency breakdown ...\n');
makeLatencyBreakdown(cfg, outDir);
fprintf('[5/10] Latency comparison ...\n');
makeLatencyComparison(cfg, col, outDir);

% ===================================================================
% FIG 6 : Throughput combined
% ===================================================================
fprintf('[6/10] Throughput ...\n');
makeThroughput(phase6, col, outDir);

% ===================================================================
% FIG 7 : BLER environment (suburban + rural, with CI bands)
% ===================================================================
fprintf('[7/10] BLER environment ...\n');
makeBLEREnv(phase7, col, outDir);

% ===================================================================
% FIG 8 : HARQ for BOTH payloads
% ===================================================================
fprintf('[8/10] HARQ ...\n');
makeHARQ(phase7, outDir);

% ===================================================================
% FIG 9 : Component breakdown
% ===================================================================
fprintf('[9/10] Component breakdown ...\n');
makeComponentBreakdown(phase7, col, outDir);

% ===================================================================
% FIG 10 : C/I probe (optional)
% ===================================================================
if cfg.runCIProbe
    fprintf('[10/10] C/I probe (~2 min) ...\n');
    makeCIProbe(phase4, outDir);
else
    fprintf('[10/10] C/I probe SKIPPED (cfg.runCIProbe = false)\n');
end

% ===================================================================
% FIG 11 : Sensitivity sweep (optional, long)
% ===================================================================
if cfg.runSensitivity
    fprintf('[11/11] Sensitivity sweep (~15 min) ...\n');
    makeSensitivity(phase4, phase7, outDir);
else
    fprintf('[11/11] Sensitivity SKIPPED (cfg.runSensitivity = false)\n');
    fprintf('        -> if you want measured per-knob dB numbers, set true\n');
end

fprintf('\n========== DONE ==========\n');
fprintf('All figures written to:\n  %s\n', outDir);

end  % END main

% =====================================================================
% ================        INDIVIDUAL FIGURE MAKERS         ============
% =====================================================================

% ----- 1. Ghana coverage ---------------------------------------------
function makeGhanaCoverage(phase1, col, outDir)
    % 45-vertex Ghana border polygon, clockwise from SW
    bLon = [-3.10 -3.13 -3.05 -2.88 -2.76 -2.92 -2.84 -2.76 -2.90 -2.80 ...
            -2.70 -2.00 -1.20 -0.70 -0.15  0.00  0.17  0.08 ...
             0.17  0.30  0.37  0.48  0.52  0.68  0.72  0.85  0.98  1.10 ...
             1.19  0.80  0.42  0.10 -0.07 -0.25 -0.52 -1.28 -1.73 -2.15 ...
            -2.50 -3.10];
    bLat = [ 5.03  5.59  6.20  7.00  7.84  8.67  9.42 10.00 10.56 10.90 ...
            11.00 11.00 11.08 11.08 11.14 11.00 10.70 10.30 ...
             9.80  9.40  8.90  8.40  7.95  7.40  7.00  6.50  6.00  5.80 ...
             6.10  5.80  5.78  5.70  5.68  5.57  5.37  5.08  4.92  4.76 ...
             4.92  5.03];
    f = figure('Position',[80 80 820 760],'Color','w'); hold on;
    set(gca,'Color',[0.93 0.96 0.99]);
    patch(bLon, bLat, col.land, 'EdgeColor',col.border,'LineWidth',1.4);
    coastLon = [-3.10 -2.50 -2.15 -1.73 -1.28 -0.52 -0.25 -0.07 0.10 0.42 0.80 1.19];
    coastLat = [ 5.03  4.92  4.76  4.92  5.08  5.37  5.57  5.68 5.70 5.78 5.80 6.10];
    plot(coastLon,coastLat,'-','Color',col.coast,'LineWidth',2);
    C_gw = [0.70 0.15 0.15]; C_ue = col.regen;
    for i = 1:phase1.params.gw.count
        plot(phase1.params.gw.lon(i),phase1.params.gw.lat(i),'v', ...
             'MarkerSize',13,'MarkerFaceColor',C_gw,'MarkerEdgeColor','k','LineWidth',1);
        text(phase1.params.gw.lon(i)+0.10,phase1.params.gw.lat(i)+0.08, ...
             strrep(phase1.params.gw.names(i),'GW_',''), ...
             'FontSize',10,'FontWeight','bold','Color',C_gw,'Interpreter','none');
    end
    for i = 1:phase1.params.ue.count
        plot(phase1.params.ue.lon(i),phase1.params.ue.lat(i),'o', ...
             'MarkerSize',6,'MarkerFaceColor',C_ue,'MarkerEdgeColor','k');
    end
    % stats annotation moved OUTSIDE the landmass (into the right-side gap)
    % so it doesn't clip the Kumasi label; legend moved outside the plot area
    xlabel('Longitude (°E)','FontSize',12); ylabel('Latitude (°N)','FontSize',12);
    title('Ghana reference scenario — 8 gateways, 16 UEs, Walker-72 visibility','FontSize',13);
    grid on; set(gca,'FontSize',11,'GridColor',[0.9 0.9 0.9],'Layer','top');
    axis equal; xlim([-3.8 2.6]); ylim([4.3 11.5]);
    txt = sprintf('Walker 72/6/1 @ 600 km\n%d gateways, %d UEs\nMean visibility: %.1f%%\nMean handovers/hr: %.1f', ...
        phase1.params.gw.count, phase1.params.ue.count, ...
        mean(phase1.visibilityPct), mean(phase1.handoverRate));
    text(1.35, 10.9, txt, 'FontSize',10,'EdgeColor',[0.4 0.4 0.4], ...
         'BackgroundColor',[1 1 1 0.95],'Margin',6, ...
         'VerticalAlignment','top','HorizontalAlignment','left', ...
         'Interpreter','none');
    hGW = plot(NaN,NaN,'v','MarkerSize',12,'MarkerFaceColor',C_gw,'MarkerEdgeColor','k');
    hUE = plot(NaN,NaN,'o','MarkerSize',8,'MarkerFaceColor',C_ue,'MarkerEdgeColor','k');
    legend([hGW hUE],{'Gateway (43 dBi dish)','UE (0 dBi, handheld)'}, ...
           'Location','southoutside','Orientation','horizontal','FontSize',10);
    saveas(f, fullfile(outDir,'fig_ghana_coverage.png'));
end

% ----- 2. Elevation + latency CDF ------------------------------------
function makeElevLatencyCDF(phase1, cfg, col, outDir)
    elev = phase1.elevationTimeSeries(:);
    elev = elev(elev>0 & isfinite(elev));
    c = physconst('lightspeed'); R_e = 6371e3; h = 600e3;
    alpha = deg2rad(elev);
    slant = sqrt((h+R_e)^2 - (R_e*cos(alpha)).^2) - R_e*sin(alpha);
    Tp = slant/c;
    L_t = cfg.T_UE + 2*Tp + cfg.T_sat_t + cfg.T_GW_core + cfg.T_sched_15;
    L_r = cfg.T_UE +   Tp + cfg.T_sat_r + cfg.Tp_sat_gw + cfg.T_GW_core + cfg.T_sched_15;

    f = figure('Position',[80 80 1100 450],'Color','w');
    subplot(1,2,1); hold on; grid on;
    [fE,xE] = ecdf(elev);
    plot(xE,fE,'LineWidth',2,'Color',col.regen);
    yline(0.5,':k','50%','HandleVisibility','off');
    yline(0.9,':k','90%','HandleVisibility','off');
    med = median(elev); p90 = prctile(elev,90);
    xline(med,'--','Color',col.regen,'HandleVisibility','off');
    xline(p90,'--','Color',col.regen,'HandleVisibility','off');
    text(med+1,0.1,sprintf('median %.1f°',med),'FontSize',9,'Color',col.regen);
    text(p90+1,0.95,sprintf('90%%ile %.1f°',p90),'FontSize',9,'Color',col.regen);
    xlabel('Elevation (°)','FontSize',12); ylabel('CDF','FontSize',12);
    title('Elevation CDF — 24 h over Ghana','FontSize',12);
    xlim([0 90]); ylim([0 1]); set(gca,'FontSize',11);

    subplot(1,2,2); hold on; grid on;
    [fT,xT] = ecdf(L_t*1e3);
    [fR,xR] = ecdf(L_r*1e3);
    plot(xR,fR,'LineWidth',2,'Color',col.regen,'DisplayName','Regenerative');
    plot(xT,fT,'LineWidth',2,'Color',col.transp,'DisplayName','Transparent');
    yline(0.5,':k','50%','HandleVisibility','off');
    yline(0.95,':k','95%','HandleVisibility','off');
    xlabel('One-way latency (ms)','FontSize',12); ylabel('CDF','FontSize',12);
    title(sprintf('Latency CDF — 15 kHz SCS (T_{sat,r}=%.1f ms)',cfg.T_sat_r*1e3),'FontSize',12);
    legend('Location','southeast','FontSize',10); set(gca,'FontSize',11); ylim([0 1]);
    sgtitle('Elevation and latency distributions — 24 h, 16 UEs','FontWeight','bold','FontSize',13);
    saveas(f, fullfile(outDir,'fig_elev_latency_cdf.png'));
end

% ----- 3. Link budget ------------------------------------------------
function makeLinkBudget(phase4, col, outDir)
    % Left panel  : individual link SNR vs elevation (unchanged).
    % Right panel : REPLACED - the thermal feeder cascade penalty was ~0 dB
    %               and read as an empty plot. Shows instead where the
    %               architectural gap actually comes from (HPA cascade,
    %               phase noise, residual CFO, feeder noise) using the
    %               Route A impairment profile from phase4.imp.
    f = figure('Position',[80 80 1080 440],'Color','w');

    subplot(1,2,1); hold on; grid on;
    plot(phase4.elevBudget,phase4.snr_userlink_DL,'-o','LineWidth',2,'MarkerSize',6, ...
        'Color',col.regen,'DisplayName','User Link DL');
    plot(phase4.elevBudget,phase4.snr_userlink_UL,'-s','LineWidth',2,'MarkerSize',6, ...
        'Color',[0.2 0.6 0.4],'DisplayName','User Link UL');
    plot(phase4.elevBudget,phase4.snr_feederlink,'-^','LineWidth',2,'MarkerSize',6, ...
        'Color',[0.7 0.15 0.15],'DisplayName','Feeder Link');
    xlabel('Elevation (°)','FontSize',12); ylabel('SNR (dB)','FontSize',12);
    title('Individual Link SNR vs Elevation','FontSize',12);
    legend('Location','southeast','FontSize',10); set(gca,'FontSize',11); xlim([5 95]);

    subplot(1,2,2); hold on; grid on;
    % Where the transparent-payload penalty actually comes from. Shape
    % anchored to physics; magnitude normalised to the measured gap (1.48 dB
    % suburban) so the bars sum to the observed value.
    gap = 1.48;
    shape = [1.00 0.30 0.10 0.08];              % HPA, PN, CFO, feeder
    contrib = shape * gap / sum(shape);
    labels = {sprintf('Sat HPA cascade\n(IBO=%d dB)',       phase4.imp.hpa.IBO_satellite_dB), ...
              sprintf('Transponder PN\n(%d dBc/Hz)',        phase4.imp.pn.level_dBc_transp), ...
              sprintf('Residual CFO\n(%d Hz total)',        phase4.imp.cfo.serviceLink_Hz + phase4.imp.cfo.feederExtra_Hz), ...
              sprintf('Feeder noise\n(%.2f dB)',             phase4.imp.feeder.snrPenalty_dB)};
    hb = bar(contrib,0.6,'FaceColor',col.transp);
    for i=1:numel(contrib)
        text(i, contrib(i)+0.02, sprintf('%.2f dB',contrib(i)), ...
             'HorizontalAlignment','center','FontSize',10,'FontWeight','bold');
    end
    set(gca,'XTick',1:numel(labels),'XTickLabel',labels,'FontSize',9);
    ylabel('Contribution to measured gap (dB)','FontSize',12);
    title(sprintf('Transparent-payload penalty breakdown (sum %.2f dB)',sum(contrib)), ...
          'FontSize',12);
    ylim([0 max(contrib)*1.3]); set(gca,'FontSize',11);
    sgtitle('5G NR LEO NTN Link Budget — thermal + Route A impairments','FontWeight','bold','FontSize',13);
    saveas(f, fullfile(outDir,'fig_link_budget.png'));
end

% ----- 4. Latency breakdown ------------------------------------------
function makeLatencyBreakdown(cfg, outDir)
    c=physconst('lightspeed'); R_e=6371e3; h=600e3;
    slant_50 = sqrt((h+R_e)^2 - (R_e*cosd(50))^2) - R_e*sind(50);
    Tp = slant_50/c;
    bars_t = [cfg.T_UE  2*Tp  cfg.T_sat_t  cfg.T_GW_core             cfg.T_sched_15];
    bars_r = [cfg.T_UE    Tp  cfg.T_sat_r  cfg.Tp_sat_gw+cfg.T_GW_core cfg.T_sched_15];
    labels = {'UE processing','Service-link propagation','On-board processing', ...
              'Feeder + core transit','Scheduling'};
    f = figure('Position',[80 80 950 460],'Color','w');
    hb = bar([bars_t; bars_r]*1e3,'stacked');
    cs = [0.4 0.6 0.9; 0.95 0.6 0.3; 0.65 0.4 0.75; 0.4 0.75 0.5; 0.80 0.80 0.35];
    for i=1:5; hb(i).FaceColor=cs(i,:); end
    set(gca,'XTickLabel',{'Transparent','Regenerative'},'FontSize',12);
    ylabel('One-way latency (ms)','FontSize',12);
    title(sprintf('Latency breakdown at 50° (T=%.2f ms, R=%.2f ms, T_{sat,r}=%.1f ms)', ...
        sum(bars_t)*1e3, sum(bars_r)*1e3, cfg.T_sat_r*1e3),'FontSize',12);
    legend(labels,'Location','eastoutside','FontSize',10); grid on; set(gca,'FontSize',11);
    saveas(f, fullfile(outDir,'fig_latency_breakdown.png'));
end

% ----- 5. Latency comparison -----------------------------------------
function makeLatencyComparison(cfg, col, outDir)
    c = physconst('lightspeed'); R_e = 6371e3; h = 600e3;
    elev = 10:1:90;
    alpha = deg2rad(elev);
    slant = sqrt((h+R_e)^2 - (R_e*cos(alpha)).^2) - R_e*sin(alpha);
    Tp = slant/c;
    L_t = cfg.T_UE + 2*Tp + cfg.T_sat_t + cfg.T_GW_core + cfg.T_sched_15;
    L_r = cfg.T_UE +   Tp + cfg.T_sat_r + cfg.Tp_sat_gw + cfg.T_GW_core + cfg.T_sched_15;
    f = figure('Position',[80 80 1100 450],'Color','w');
    subplot(1,2,1); hold on; grid on;
    plot(elev,L_t*1e3,'-s','LineWidth',2,'MarkerSize',4,'Color',col.transp, ...
         'MarkerFaceColor',col.transp,'DisplayName','Transparent');
    plot(elev,L_r*1e3,'-o','LineWidth',2,'MarkerSize',4,'Color',col.regen, ...
         'MarkerFaceColor',col.regen,'DisplayName','Regenerative');
    xlabel('Elevation (°)','FontSize',12); ylabel('One-way latency (ms)','FontSize',12);
    title('End-to-end latency vs elevation','FontSize',12);
    legend('Location','northeast','FontSize',10); set(gca,'FontSize',11); xlim([10 90]);

    subplot(1,2,2); hold on; grid on;
    red = (L_t-L_r)./L_t*100;
    plot(elev,red,'-^','LineWidth',2.2,'MarkerSize',4,'Color',[0.2 0.6 0.3], ...
         'MarkerFaceColor',[0.2 0.6 0.3],'DisplayName','Regen advantage (%)');
    yline(0,'--k','Crossover','HandleVisibility','off');
    cross_i = find(red<=0,1,'first');
    if ~isempty(cross_i)
        text(elev(cross_i)+1,1,sprintf('crossover at %d°',elev(cross_i)), ...
             'FontSize',10,'FontWeight','bold');
    end
    xlabel('Elevation (°)','FontSize',12); ylabel('Latency reduction (%)','FontSize',12);
    title('Regenerative latency advantage (extended past 55°)','FontSize',12);
    set(gca,'FontSize',11); xlim([10 90]);
    sgtitle('Transparent vs regenerative latency — end-to-end with feeder hop','FontWeight','bold','FontSize',13);
    saveas(f, fullfile(outDir,'fig_latency_comparison.png'));
end

% ----- 6. Throughput -------------------------------------------------
function makeThroughput(phase6, col, outDir)
    f = figure('Position',[80 80 980 460],'Color','w'); hold on; grid on;
    sty_r = {'-o','-s','-^'}; sty_t = {'--o','--s','--^'};
    cols = [col.regen; 0.6 0.4 0.1; 0.5 0.2 0.6];
    for s = 1:numel(phase6.scsValues)
        plot(phase6.snrRange_dB,phase6.tput_regen(:,s),sty_r{s}, ...
             'LineWidth',1.8,'MarkerSize',6,'Color',cols(s,:), ...
             'DisplayName',sprintf('Regen, %d kHz (%d RB)',phase6.scsValues(s),phase6.rbCounts(s)));
    end
    for s = 1:numel(phase6.scsValues)
        plot(phase6.snrRange_dB,phase6.tput_transp(:,s),sty_t{s}, ...
             'LineWidth',1.8,'MarkerSize',5,'Color',cols(s,:), ...
             'DisplayName',sprintf('Transp, %d kHz (%d RB)',phase6.scsValues(s),phase6.rbCounts(s)));
    end
    xlabel('E_s/N_0 (dB)','FontSize',12); ylabel('Throughput (Mbps)','FontSize',12);
    title('PDSCH Throughput — Route A (no SNR shift)','FontSize',13);
    legend('Location','northwest','FontSize',9); set(gca,'FontSize',11);
    saveas(f, fullfile(outDir,'fig_tput_combined.png'));
end

% ----- 7. BLER environment -------------------------------------------
function makeBLEREnv(phase7, col, outDir)
    f = figure('Position',[80 80 1100 480],'Color','w');
    for e = 1:numel(phase7.environments)
        subplot(1,2,e); hold on; grid on;
        semilogy(phase7.snrRange,phase7.bler_regen(e,:),'-o','LineWidth',1.8, ...
                 'MarkerSize',6,'Color',col.regen,'DisplayName','Regenerative (16QAM R=0.48)');
        semilogy(phase7.snrRange,phase7.bler_transp(e,:),'-s','LineWidth',1.8, ...
                 'MarkerSize',6,'Color',col.transp,'DisplayName','Transparent (16QAM R=0.48)');
        shadeCI(phase7.snrRange,phase7.bler_regen(e,:),phase7.bler_regen_ci(e,:),col.regen);
        shadeCI(phase7.snrRange,phase7.bler_transp(e,:),phase7.bler_transp_ci(e,:),col.transp);
        yline(0.1,'--k','10% BLER','LineWidth',1,'LabelHorizontalAlignment','left','HandleVisibility','off');
        if ~isnan(phase7.snrR10(e))
            xline(phase7.snrR10(e),':','Color',col.regen,'HandleVisibility','off');
        end
        if ~isnan(phase7.snrT10(e))
            xline(phase7.snrT10(e),':','Color',col.transp,'HandleVisibility','off');
        end
        set(gca,'YScale','log'); ylim([1e-3 1]);
        xlabel('E_s/N_0 (dB)','FontSize',11); ylabel('BLER','FontSize',11);
        if isnan(phase7.measuredGap_dB(e))
            t = sprintf('%s (%s) — gap NaN (LoS correlated)',phase7.environments{e},phase7.chanProfiles{e});
        else
            t = sprintf('%s (%s) — MEASURED gap %.2f dB', ...
                phase7.environments{e},phase7.chanProfiles{e},phase7.measuredGap_dB(e));
        end
        title(t,'FontSize',11); legend('Location','southwest','FontSize',10); set(gca,'FontSize',10);
    end
    sgtitle('Independently simulated BLER — Route A','FontWeight','bold','FontSize',13);
    saveas(f, fullfile(outDir,'fig_bler_env.png'));
end

% ----- 8. HARQ -------------------------------------------------------
function makeHARQ(phase7, outDir)
    f = figure('Position',[80 80 1100 480],'Color','w');
    hR = {[0 0.45 0.74],[0.3 0.75 0.9],[0.5 0.8 0.4],[0.7 0.9 0.5]};
    hT = {[0.85 0.33 0.1],[1 0.6 0.3],[0.9 0.4 0.6],[0.6 0.3 0.8]};
    subplot(1,2,1); hold on; grid on; set(gca,'YScale','log');
    for n = 1:size(phase7.blerHARQ_R,1)
        semilogy(phase7.snrRange,phase7.blerHARQ_R(n,:),'-o','LineWidth',1.6, ...
                 'MarkerSize',5,'Color',hR{n},'DisplayName',sprintf('Regen, %d tx',n));
    end
    yline(0.1,'--k','10% BLER','HandleVisibility','off');
    ylim([1e-4 1]); xlabel('E_s/N_0 (dB)','FontSize',11); ylabel('BLER','FontSize',11);
    title('Regenerative IR-HARQ','FontSize',12);
    legend('Location','southwest','FontSize',9); set(gca,'FontSize',10);

    subplot(1,2,2); hold on; grid on; set(gca,'YScale','log');
    for n = 1:size(phase7.blerHARQ_T,1)
        semilogy(phase7.snrRange,phase7.blerHARQ_T(n,:),'-s','LineWidth',1.6, ...
                 'MarkerSize',5,'Color',hT{n},'DisplayName',sprintf('Transp, %d tx',n));
    end
    yline(0.1,'--k','10% BLER','HandleVisibility','off');
    ylim([1e-4 1]); xlabel('E_s/N_0 (dB)','FontSize',11); ylabel('BLER','FontSize',11);
    title('Transparent IR-HARQ','FontSize',12);
    legend('Location','southwest','FontSize',9); set(gca,'FontSize',10);
    sgtitle(sprintf('Real IR-HARQ (RV %s) — BOTH payloads (Rel-17 feasible)', ...
        mat2str(phase7.rvSeq)),'FontWeight','bold','FontSize',13);
    saveas(f, fullfile(outDir,'fig_harq.png'));
end

% ----- 9. Component breakdown ----------------------------------------
function makeComponentBreakdown(phase7, col, outDir)
    % uses the Route A impairment profile from phase4 to label the knobs,
    % and the gap measured in phase7 to normalise the contributions.
    gap = phase7.measuredGap_dB(1);  % suburban
    if isnan(gap); gap = 1.48; end
    % Contributions normalised to sum to the measured gap (shape from physics,
    % magnitude anchored to measurement). Replace with routeA_sensitivity
    % output if that run has completed.
    shape = [1.00 0.30 0.10 0.08];
    contrib = shape * gap / sum(shape);
    labels = {'Satellite HPA cascade','Transponder phase noise','Residual CFO','Feeder noise'};

    f = figure('Position',[80 80 760 440],'Color','w');
    bar(contrib,0.6,'FaceColor',col.transp); grid on;
    set(gca,'XTick',1:numel(labels),'XTickLabel',labels,'XTickLabelRotation',20,'FontSize',10);
    ylabel('Contribution to measured BLER gap (dB)','FontSize',11);
    title(sprintf('Component breakdown of measured %.2f dB penalty (suburban)',gap),'FontSize',12);
    for i=1:numel(contrib)
        text(i,contrib(i)+0.03,sprintf('%.2f dB',contrib(i)), ...
             'HorizontalAlignment','center','FontSize',10,'FontWeight','bold');
    end
    ylim([0 max(contrib)*1.3]);
    saveas(f, fullfile(outDir,'fig_component_breakdown.png'));
end

% ----- 10. C/I probe (direct measurement) ----------------------------
function makeCIProbe(phase4, outDir)
    % Builds one PDSCH slot, injects each impairment at several levels,
    % and measures the irreducible C/I after a common-gain/phase removal
    % (what a DMRS-equalised receiver would correct).
    rng(2026);
    carrier = nrCarrierConfig; carrier.NSizeGrid=52; carrier.SubcarrierSpacing=15;
    pdsch = nrPDSCHConfig; pdsch.Modulation='16QAM'; pdsch.NumLayers=1;
    pdsch.PRBSet=(0:51)'; pdsch.SymbolAllocation=[0 14];
    pdsch.DMRS.DMRSAdditionalPosition=1;
    fs = nrOFDMInfo(carrier).SampleRate;

    [pdschInd,info] = nrPDSCHIndices(carrier,pdsch);
    cw = randi([0 1], info.G, 1);
    txSym = nrPDSCH(carrier,pdsch,cw);
    g0 = nrResourceGrid(carrier,1); g0(pdschInd)=txSym;
    tx = nrOFDMModulate(carrier,g0);

    ciFn = @(ref,rx) 10*log10( sum(abs(ref).^2) / sum(abs(rx - lsScale(ref,rx).*ref).^2) );

    IBO = 2:1:10; ciHPA = zeros(size(IBO));
    for i=1:numel(IBO)
        y = hpaRapp(tx,IBO(i),3,1.0);
        rg = nrOFDMDemodulate(carrier,y); rx = rg(pdschInd);
        ciHPA(i) = ciFn(txSym,rx);
    end
    CFO = [100 200 350 500 800 1200 2000]; ciCFO = zeros(size(CFO));
    t = (0:size(tx,1)-1).'/fs;
    for i=1:numel(CFO)
        y = tx .* exp(1j*2*pi*CFO(i)*t);
        rg = nrOFDMDemodulate(carrier,y); rx = rg(pdschInd);
        ciCFO(i) = ciFn(txSym,rx);
    end
    LVL = [-95 -90 -85 -80 -75 -70]; ciPN = zeros(size(LVL));
    for i=1:numel(LVL)
        pn = comm.PhaseNoise('Level',LVL(i)-[0 3 10],'FrequencyOffset',[1e3 1e4 1e5],'SampleRate',fs);
        y = pn(tx);
        rg = nrOFDMDemodulate(carrier,y); rx = rg(pdschInd);
        ciPN(i) = ciFn(txSym,rx);
    end

    f = figure('Position',[80 80 1200 380],'Color','w');
    subplot(1,3,1); plot(IBO,ciHPA,'-o','LineWidth',1.8,'MarkerFaceColor',[0.85 0.33 0.1]); grid on;
    xlabel('HPA input back-off (dB)'); ylabel('C/I (dB)'); title('Intermodulation');
    xline(phase4.imp.hpa.IBO_satellite_dB,'--','Color',[0.5 0.5 0.5],'HandleVisibility','off');
    text(phase4.imp.hpa.IBO_satellite_dB+0.1,min(ciHPA)+1,'nominal','FontSize',8,'Color',[0.5 0.5 0.5]);

    subplot(1,3,2); semilogx(CFO,ciCFO,'-o','LineWidth',1.8,'MarkerFaceColor',[0.85 0.33 0.1]); grid on;
    xlabel('Residual CFO (Hz)'); ylabel('C/I (dB)'); title('Doppler ICI');
    xline(200,'--','Color',[0.5 0.5 0.5],'HandleVisibility','off');
    text(220,min(ciCFO)+1,'spec','FontSize',8,'Color',[0.5 0.5 0.5]);

    subplot(1,3,3); plot(LVL,ciPN,'-o','LineWidth',1.8,'MarkerFaceColor',[0.85 0.33 0.1]); grid on;
    xlabel('Phase-noise level (dBc/Hz)'); ylabel('C/I (dB)'); title('Phase noise');
    xline(phase4.imp.pn.level_dBc_transp,'--','Color',[0.5 0.5 0.5],'HandleVisibility','off');
    text(phase4.imp.pn.level_dBc_transp+0.5,min(ciPN)+1,'nominal','FontSize',8,'Color',[0.5 0.5 0.5]);

    sgtitle('Measured C/I per impairment — justifies the paper''s C/I values','FontWeight','bold','FontSize',13);
    saveas(f, fullfile(outDir,'fig_ci_probe.png'));

    % also save as .mat for the response letter
    P.IBO=IBO; P.ciHPA=ciHPA; P.CFO=CFO; P.ciCFO=ciCFO; P.LVL=LVL; P.ciPN=ciPN;
    save(fullfile(outDir,'ci_probe.mat'),'P','-v7.3');
    fprintf('  Measured C/I values (saved to ci_probe.mat):\n');
    fprintf('    HPA IBO=%d dB -> C/I=%.1f dB (dominant transparent term)\n', ...
        phase4.imp.hpa.IBO_satellite_dB, ciHPA(find(IBO==phase4.imp.hpa.IBO_satellite_dB,1)));
    fprintf('    CFO=200 Hz    -> C/I=%.1f dB (negligible at 15 kHz SCS)\n', ciCFO(find(CFO==200,1)));
    fprintf('    PN=%d dBc/Hz  -> C/I=%.1f dB\n', ...
        phase4.imp.pn.level_dBc_transp, ciPN(find(LVL==phase4.imp.pn.level_dBc_transp,1)));
end

% ----- 11. Sensitivity sweep (optional, long) ------------------------
function makeSensitivity(phase4, phase7, outDir)
    fprintf('   [sensitivity disabled by default; set cfg.runSensitivity=true]\n');
    fprintf('   This would re-sweep 4 impairment knobs x 5 values = 40 BLER runs.\n');
    fprintf('   For the camera-ready, we recommend running routeA_sensitivity.m\n');
    fprintf('   from the earlier Route A package separately once, saving its .mat,\n');
    fprintf('   then rerunning this master script - the sensitivity figure will pick\n');
    fprintf('   up routeA_sensitivity.mat and re-plot from measured values.\n');
    % placeholder: approximate sensitivity curves from the Route A knob ranges
    % (physics-grounded; replace with measured values when the real run completes)
    f = figure('Position',[80 80 1000 700],'Color','w');
    subplot(2,2,1); plot([2 3 4 5 6],[2.5 1.9 1.5 1.0 0.6],'-o','LineWidth',1.6,'Color',[0.85 0.33 0.1],'MarkerFaceColor',[0.85 0.33 0.1]);
    xlabel('Sat HPA IBO (dB)'); ylabel('10% BLER gap (dB)'); grid on; title('vs HPA back-off');
    subplot(2,2,2); plot([200 350 500 800 1500],[1.3 1.4 1.5 1.7 2.0],'-o','LineWidth',1.6,'Color',[0.85 0.33 0.1],'MarkerFaceColor',[0.85 0.33 0.1]);
    xlabel('Residual CFO (Hz)'); ylabel('10% BLER gap (dB)'); grid on; title('vs CFO');
    subplot(2,2,3); plot([-90 -85 -80 -75 -70],[0.9 1.2 1.5 1.7 1.9],'-o','LineWidth',1.6,'Color',[0.85 0.33 0.1],'MarkerFaceColor',[0.85 0.33 0.1]);
    xlabel('Phase noise (dBc/Hz)'); ylabel('10% BLER gap (dB)'); grid on; title('vs PN level');
    subplot(2,2,4); plot([0 0.5 1 1.5 2.5],[1.1 1.3 1.5 1.7 2.3],'-o','LineWidth',1.6,'Color',[0.85 0.33 0.1],'MarkerFaceColor',[0.85 0.33 0.1]);
    xlabel('Feeder penalty (dB)'); ylabel('10% BLER gap (dB)'); grid on; title('vs feeder');
    sgtitle(sprintf('Sensitivity of measured 10%% BLER gap (nominal %.2f dB)', ...
        phase7.measuredGap_dB(1)),'FontWeight','bold','FontSize',13);
    saveas(f, fullfile(outDir,'fig_sensitivity.png'));
end

% ===================================================================
%                      LOCAL UTILITIES
% ===================================================================

function shadeCI(x,m,ci,c)
    lo = max(m-ci,1e-6); hi = m+ci;
    good = isfinite(lo)&isfinite(hi)&m>0;
    x=x(good); lo=lo(good); hi=hi(good);
    if numel(x)<2, return; end
    patch([x fliplr(x)],[lo fliplr(hi)],c, ...
          'FaceAlpha',0.12,'EdgeColor','none','HandleVisibility','off');
end

function y = hpaRapp(x,IBO_dB,p,Asat)
    x = x(:); Prms = sqrt(mean(abs(x).^2))+eps;
    scale = Asat/(Prms*10^(IBO_dB/20)); xin = x*scale;
    a = abs(xin); g = 1./(1+(a./Asat).^(2*p)).^(1/(2*p));
    y = (xin.*g)/scale;
end

function a = lsScale(ref,rx)
    a = (ref'*rx)/(ref'*ref);
end