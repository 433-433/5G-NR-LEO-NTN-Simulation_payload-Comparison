%% ========================================================================
%  ROUTE A : SENSITIVITY ANALYSIS of the transparent-payload penalty
%  ========================================================================
%  Reviewer #2: "test how sensitive the conclusions are to these assumptions."
%
%  Holds the regenerative payload at its baseline and sweeps, ONE AT A TIME,
%  the four transparent-payload impairment knobs:
%     (1) satellite transponder HPA input back-off  (intermodulation)
%     (2) residual carrier frequency offset          (Doppler ICI)
%     (3) oscillator phase-noise level               (phase noise)
%     (4) feeder-link SNR penalty                     (noise accumulation)
%  For each value it re-measures the 10% BLER gap vs the fixed regenerative
%  reference, so the paper can show the penalty is not an artefact of one
%  lucky assumption. Produces a tornado-style figure and a table.
%
%  REQUIRES ntnChain.m, firstCrossing.m on the path.
%  Uses a coarser grid / fewer seeds than routeA_bler.m to keep the 2-D
%  sweep tractable; raise them for the camera-ready version.
%  RUN IT YOURSELF - nothing here is a result until you do.
%  ========================================================================
clc; clear; close all; rng(2026);
outDir = fullfile(pwd,'results_routeA');
if ~exist(outDir,'dir'); mkdir(outDir); end

%% baseline config (lighter than the main run) --------------------------
cfg.snrRange   = -4:1:14;
cfg.nSlots     = 40;
cfg.seeds      = [73 101];
cfg.blerTarget = 0.10;
cfg.environment= 'suburban';
cfg.verbose    = false;

carrier = nrCarrierConfig; carrier.NSizeGrid=52; carrier.SubcarrierSpacing=15;
pdsch = nrPDSCHConfig; pdsch.Modulation='16QAM'; pdsch.NumLayers=1;
pdsch.PRBSet=0:carrier.NSizeGrid-1; pdsch.SymbolAllocation=[0 14];
pdsch.DMRS.DMRSAdditionalPosition=1;
R = 490/1024; fs = nrOFDMInfo(carrier).SampleRate;

% impairment baseline (same as routeA_bler.m)
imp.hpa.smoothness=3; imp.hpa.satLevel=1.0;
imp.hpa.IBO_regen_dB=8; imp.hpa.IBO_gatewayTx_dB=7; imp.hpa.IBO_satellite_dB=4;
imp.cfo.serviceLink_Hz=200; imp.cfo.feederExtra_Hz=300;
imp.pn.level_dBc_regen=-85; imp.pn.level_dBc_transp=-80; imp.pn.foffset_Hz=[1e3 1e4 1e5];
imp.feeder.snrPenalty_dB=1.0;
imp.chan.profile='TDL-C'; imp.chan.DS=50e-9;
fc=2e9; c=physconst('lightspeed'); fd=(3*1000/3600)*fc/c;
imp.chan.fd_regen_Hz=fd; imp.chan.fd_transp_Hz=fd+50;

baseR = struct('name','Regen','hpaIBO_dB',imp.hpa.IBO_regen_dB,'hpaCascade',false, ...
    'hpaIBO2_dB',NaN,'cfo_Hz',imp.cfo.serviceLink_Hz,'pn_dBc',imp.pn.level_dBc_regen, ...
    'feederPenalty_dB',0,'fd_Hz',imp.chan.fd_regen_Hz);
baseT = struct('name','Transp','hpaIBO_dB',imp.hpa.IBO_gatewayTx_dB,'hpaCascade',true, ...
    'hpaIBO2_dB',imp.hpa.IBO_satellite_dB, ...
    'cfo_Hz',imp.cfo.serviceLink_Hz+imp.cfo.feederExtra_Hz, ...
    'pn_dBc',imp.pn.level_dBc_transp,'feederPenalty_dB',imp.feeder.snrPenalty_dB, ...
    'fd_Hz',imp.chan.fd_transp_Hz);

%% fixed regenerative reference -----------------------------------------
fprintf('Regenerative reference ...\n');
blerR = meanBLER(carrier,pdsch,R,fs,cfg,imp,baseR);
snrR10 = firstCrossing(cfg.snrRange, blerR, cfg.blerTarget);
fprintf('  Regen 10%%-BLER = %.2f dB\n', snrR10);

%% sweeps ----------------------------------------------------------------
sweeps(1) = struct('name','Sat HPA IBO (dB)','field','hpaIBO2_dB','vals',[2 3 4 5 6]);
sweeps(2) = struct('name','Residual CFO (Hz)','field','cfo_Hz','vals',[200 350 500 800 1500]);
sweeps(3) = struct('name','Phase noise (dBc/Hz)','field','pn_dBc','vals',[-90 -85 -80 -75 -70]);
sweeps(4) = struct('name','Feeder penalty (dB)','field','feederPenalty_dB','vals',[0 0.5 1 1.5 2.5]);

results = struct();
for i = 1:numel(sweeps)
    sw = sweeps(i); gaps = nan(size(sw.vals));
    fprintf('\nSweep: %s\n', sw.name);
    for j = 1:numel(sw.vals)
        p = baseT; p.(sw.field) = sw.vals(j);
        blerT = meanBLER(carrier,pdsch,R,fs,cfg,imp,p);
        snrT10 = firstCrossing(cfg.snrRange, blerT, cfg.blerTarget);
        gaps(j) = snrT10 - snrR10;
        fprintf('   %-22s = %-7.4g -> gap %.2f dB\n', sw.field, sw.vals(j), gaps(j));
    end
    results.(sprintf('sweep%d',i)) = struct('name',sw.name,'vals',sw.vals,'gaps',gaps);
end

%% figure: one panel per knob -------------------------------------------
f=figure('Position',[80 80 1000 700],'Color','w');
for i=1:numel(sweeps)
    subplot(2,2,i);
    s=results.(sprintf('sweep%d',i));
    plot(s.vals, s.gaps,'-o','LineWidth',1.6,'MarkerFaceColor',[0.85 0.33 0.10], ...
        'Color',[0.85 0.33 0.10]); grid on;
    xlabel(s.name); ylabel('10% BLER gap (dB)');
    title(sprintf('Penalty vs %s', s.name),'FontSize',10);
end
sgtitle('Route A sensitivity: transparent-payload penalty vs each assumption');
saveas(f, fullfile(outDir,'routeA_sensitivity.png'));

%% save ------------------------------------------------------------------
S.snrR10=snrR10; S.sweeps=results; S.cfg=cfg; S.imp=imp;
save(fullfile(outDir,'routeA_sensitivity.mat'),'S','-v7.3');
fprintf('\nSaved results_routeA/routeA_sensitivity.{png,mat}\n');
fprintf('>> Send me routeA_sensitivity.mat and I turn it into the sensitivity table/figure.\n');

%% ----------------------------------------------------------------------
function b = meanBLER(carrier,pdsch,R,fs,cfg,imp,prof)
    acc = zeros(numel(cfg.seeds), numel(cfg.snrRange));
    for si=1:numel(cfg.seeds)
        acc(si,:) = ntnChain(carrier,pdsch,R,fs,cfg,imp,prof,cfg.seeds(si));
    end
    b = mean(acc,1,'omitnan');
end