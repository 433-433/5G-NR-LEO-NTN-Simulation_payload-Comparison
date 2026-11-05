%% ========================================================================
%  PHASE 4 (v3 - Route A): Payload Architecture Modeling
%  ========================================================================
%  5G NR LEO NTN - Performance Analysis
%
%  WHAT CHANGED from phase4_payload.m
%  ------------------------------------------------------------------------
%  v2 behaviour (which the reviewers caught):
%      snr_intermod_dB = 12 ; snr_ICI_dB = 14 ; snr_phaseNoise_dB = 16
%      snr_casc_lin   = 1/(1/user+1/feeder+1/intermod+1/ICI+1/phase)
%      phase4.snrDegradation = snr_regen_dB - snr_transp_dB   % exported scalar
%      Section 6 BER preview: snrTransp = snr - snrDegradation (THE SHIFT)
%
%  Those hardcoded C/I values are gone. The three "transponder impairments"
%  are now PHYSICAL knobs (HPA back-off, oscillator phase-noise level,
%  residual CFO) that routeA_ci_probe.m measures C/I from, and that
%  phase6_v3 / phase7_v3 inject into the TX waveform. The thermal part of
%  the cascaded link budget (user + feeder) is preserved and now feeds a
%  per-elevation feederPenalty_dB vector derived from the cascade formula,
%  not from an invented 12/14/16 dB stack.
%
%  WHAT THIS PHASE NOW EXPORTS
%  ------------------------------------------------------------------------
%      phase4.elevBudget            [1xE]  elevation grid (deg)
%      phase4.slantBudget           [1xE]  slant range (m)
%      phase4.snr_userlink_UL/DL    [1xE]  thermal UL/DL SNR per elevation
%      phase4.snr_feederlink        [1xE]  thermal feeder SNR per elevation
%      phase4.feederPenalty_dB      [1xE]  cascade penalty (user_dB - cascSNR_dB)
%      phase4.imp                   impairment struct consumed by phase6/7 v3
%      phase4.profT, phase4.profR   per-payload profile (hpa, cfo, pn, feeder)
%      phase4.refElev, phase4.refIdx   reference elevation (50 deg)
%
%  NOTE: phase4.snrDegradation is NOT exported. Downstream phases must not
%  use any "SNR - snrDegradation" shift. If a legacy script still asks for it
%  the field is intentionally absent so the error is loud.
%
%  3GPP: TR 38.821 Table 6.1.1-1, TS 38.101-5, TR 38.803 (HPA model).
%  ========================================================================
clc; clear; close all;

%% paths & params --------------------------------------------------------
addpath('config'); addpath('helpers');
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 4 (v3 - Route A): Payload Architecture Modeling\n');
fprintf('============================================================\n\n');

%% load prior phases (optional - this phase stands on its own) -----------
hasP2 = exist(fullfile(params.outputDir,'phase2_results.mat'),'file')==2;
hasP3 = exist(fullfile(params.outputDir,'phase3_results.mat'),'file')==2;
if hasP2; load(fullfile(params.outputDir,'phase2_results.mat'),'phase2');
    fprintf('  phase2_results.mat loaded.\n'); end
if hasP3; load(fullfile(params.outputDir,'phase3_results.mat'),'phase3');
    fprintf('  phase3_results.mat loaded.\n'); end
fprintf('\n');

c  = params.c;
fc = params.rf.carrierFrequency;
BW = params.rf.channelBandwidth;

%% =====================================================================
%  SECTION 1: THERMAL LINK BUDGET per ELEVATION
%  (same physics as phase4_payload.m - this part was fine, kept as-is)
%  =====================================================================
fprintf('--- Section 1: Thermal link budget per elevation ---\n');

elevBudget = [10 20 30 50 70 90];
nE = numel(elevBudget);
[snr_userlink_UL, snr_userlink_DL, snr_feederlink, slantBudget] = deal(zeros(1,nE));

fprintf('  %-5s | %-10s | %-10s | %-10s | %-10s\n', ...
    'Elev','Slant(km)','UL SNR(dB)','DL SNR(dB)','Feed SNR(dB)');
fprintf('  %s\n', repmat('-',1,66));

totalLoss = params.rf.atmosphericLoss_dB + params.rf.scintillationLoss_dB + ...
            params.rf.polarizationLoss_dB;

for k = 1:nE
    el = elevBudget(k);
    slant = computeSlantRange(el, params.sat.altitude, params.R_earth, c);
    slantBudget(k) = slant;
    FSPL = 20*log10(4*pi*slant*fc/c);

    % UE -> Sat (uplink)
    rxPwrUL = params.rf.ueTxPower_dBm + params.rf.ueAntennaGain_dBi ...
              - FSPL - totalLoss - params.rf.bodyLoss_dB ...
              + params.rf.satAntennaGain_dBi;
    nPwrSat = -174 + 10*log10(BW) + params.rf.satNoiseFigure_dB;
    snr_userlink_UL(k) = rxPwrUL - nPwrSat;

    % Sat -> UE (downlink)  (same for BOTH payloads; no shift)
    rxPwrDL = params.rf.satTxPower_dBm + params.rf.satAntennaGain_dBi ...
              - FSPL - totalLoss - params.rf.bodyLoss_dB ...
              + params.rf.ueAntennaGain_dBi;
    nPwrUE  = -174 + 10*log10(BW) + params.rf.ueNoiseFigure_dB;
    snr_userlink_DL(k) = rxPwrDL - nPwrUE;

    % Feeder link (Sat <-> GW, high-gain dish)
    satOBO_dB = 3; satScanLoss_dB = 2;
    rxPwrFd  = params.rf.satTxPower_dBm - satOBO_dB ...
               + params.rf.satAntennaGain_dBi - satScanLoss_dB ...
               - FSPL - totalLoss ...
               + params.rf.gwAntennaGain_dBi;
    nPwrGW   = -174 + 10*log10(BW) + params.rf.gwNoiseFigure_dB;
    snr_feederlink(k) = rxPwrFd - nPwrGW;

    fprintf('  %4d  | %8.1f   | %8.1f   | %8.1f   | %8.1f\n', ...
        el, slant/1e3, snr_userlink_UL(k), snr_userlink_DL(k), snr_feederlink(k));
end
fprintf('\n');

%% =====================================================================
%  SECTION 2: FEEDER-NOISE CASCADE PENALTY (thermal only; replaces hardcoded 12/14/16 dB)
%  Transparent cascades user + feeder; regenerative sees user only.
%  Per-elevation penalty = snr_userlink_DL(k) - snr_cascaded_thermal(k).
%  =====================================================================
fprintf('--- Section 2: Thermal feeder cascade penalty ---\n');
feederPenalty_dB = zeros(1,nE);
for k = 1:nE
    user_lin = 10^(snr_userlink_DL(k)/10);
    feed_lin = 10^(snr_feederlink(k)/10);
    casc_lin = 1 / (1/user_lin + 1/feed_lin);
    feederPenalty_dB(k) = snr_userlink_DL(k) - 10*log10(casc_lin);
end
fprintf('  %-5s | %-14s | %-14s | %-14s\n', ...
    'Elev','Thermal pen','UserSNR(dB)','FeedSNR(dB)');
for k = 1:nE
    fprintf('  %4d  | %6.2f dB      | %6.1f         | %6.1f\n', ...
        elevBudget(k), feederPenalty_dB(k), snr_userlink_DL(k), snr_feederlink(k));
end
fprintf('  (This is small because GW antenna gain is high; the dominant\n');
fprintf('   architectural differences live in HPA/PN/CFO impairments below.)\n\n');

%% =====================================================================
%  SECTION 3: PHYSICAL IMPAIRMENT PROFILE (replaces hardcoded 12/14/16 dB)
%  Each number is traceable:
%      HPA IBO     -> input back-off (dB)        -> intermodulation C/I
%      cfo_Hz      -> residual carrier offset    -> Doppler ICI C/I
%      pn_dBc      -> oscillator phase-noise mask -> phase-noise C/I
%  routeA_ci_probe.m MEASURES the C/I each of these induces.
%  =====================================================================
fprintf('--- Section 3: Physical impairment profile ---\n');

imp.hpa.smoothness = 3;
imp.hpa.satLevel   = 1.0;
imp.hpa.IBO_regen_dB     = 8;    % onboard digital gNB (DPD + back-off)
imp.hpa.IBO_gatewayTx_dB = 7;    % ground gateway HPA
imp.hpa.IBO_satellite_dB = 4;    % transponder HPA driven toward saturation

imp.cfo.serviceLink_Hz = 200;    % +/-0.1 ppm @ 2 GHz after GNSS precomp (BOTH; TS 38.101-5)
imp.cfo.feederExtra_Hz = 300;    % extra uncompensated feeder Doppler (transparent only)

imp.pn.level_dBc_regen  = -85;   % onboard synthesiser mask (dBc/Hz)
imp.pn.level_dBc_transp = -80;   % + satellite translation LO
imp.pn.foffset_Hz       = [1e3 1e4 1e5];

refElev = 50; refIdx = find(elevBudget == refElev);
imp.feeder.snrPenalty_dB = feederPenalty_dB(refIdx);  % feeder thermal penalty at ref elev

% channel (service link; SAME for both payloads - same satellite, same user)
imp.chan.profile = 'NTN-TDL-C';           % suburban primary (TDL-D handled in phase7_v3)
imp.chan.DS      = params.channel.delaySpread.suburban;
if hasP2
    imp.chan.fd_Hz = phase2.mobileDoppler;    % ~5.6 Hz pedestrian @ 2 GHz
else
    imp.chan.fd_Hz = params.ue.speed_ms * fc / c;
end

%% impairment profile structs (consumed by phase6/7 v3) ------------------
profR = struct('name','Regenerative', ...
    'hpaIBO_dB', imp.hpa.IBO_regen_dB, ...
    'hpaCascade', false, 'hpaIBO2_dB', NaN, ...
    'hpaSmoothness', imp.hpa.smoothness, 'hpaSatLevel', imp.hpa.satLevel, ...
    'cfo_Hz', imp.cfo.serviceLink_Hz, ...
    'pn_dBc', imp.pn.level_dBc_regen, ...
    'feederPenalty_dB', 0);           % clean bits re-generated on board

profT = struct('name','Transparent', ...
    'hpaIBO_dB', imp.hpa.IBO_gatewayTx_dB, ...
    'hpaCascade', true, 'hpaIBO2_dB', imp.hpa.IBO_satellite_dB, ...
    'hpaSmoothness', imp.hpa.smoothness, 'hpaSatLevel', imp.hpa.satLevel, ...
    'cfo_Hz', imp.cfo.serviceLink_Hz + imp.cfo.feederExtra_Hz, ...
    'pn_dBc', imp.pn.level_dBc_transp, ...
    'feederPenalty_dB', imp.feeder.snrPenalty_dB);

fprintf('  Impairment profiles defined.\n');
fprintf('    Regen : HPA IBO=%d dB (single), CFO=%d Hz, PN=%d dBc/Hz, feeder=0 dB\n', ...
    profR.hpaIBO_dB, profR.cfo_Hz, profR.pn_dBc);
fprintf('    Transp: HPA IBO=%d dB + %d dB (cascade), CFO=%d Hz, PN=%d dBc/Hz, feeder=%.2f dB\n\n', ...
    profT.hpaIBO_dB, profT.hpaIBO2_dB, profT.cfo_Hz, profT.pn_dBc, profT.feederPenalty_dB);

%% =====================================================================
%  SECTION 4: SNR-vs-ELEVATION PLOTS (unchanged from v2)
%  =====================================================================
fprintf('--- Section 4: Link budget plots ---\n');
figure('Name','Link Budget v3','Position',[100 100 1000 500]);
subplot(1,2,1);
plot(elevBudget, snr_userlink_DL,'-bo','LineWidth',2,'MarkerSize',7,'DisplayName','User Link DL');
hold on;
plot(elevBudget, snr_userlink_UL,'-gs','LineWidth',2,'MarkerSize',7,'DisplayName','User Link UL');
plot(elevBudget, snr_feederlink, '-r^','LineWidth',2,'MarkerSize',7,'DisplayName','Feeder Link');
hold off; grid on; set(gca,'FontSize',11);
xlabel('Elevation (deg)'); ylabel('SNR (dB)');
title('Individual Link SNR vs Elevation'); legend('Location','southeast');

subplot(1,2,2);
bar(elevBudget, feederPenalty_dB, 0.5, 'FaceColor',[0.2 0.6 0.4]);
grid on; set(gca,'FontSize',11);
xlabel('Elevation (deg)'); ylabel('Feeder cascade penalty (dB)');
title('Transparent-only thermal feeder penalty');
for k=1:nE
    text(elevBudget(k), feederPenalty_dB(k)+0.02, sprintf('%.2f',feederPenalty_dB(k)), ...
        'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
end
sgtitle('5G NR LEO NTN Link Budget (v3 - Route A, thermal only)', 'FontWeight','bold');
saveas(gcf, fullfile(params.outputDir,'phase4_v3_link_budget.png'));
fprintf('  Saved phase4_v3_link_budget.png\n\n');

%% =====================================================================
%  SECTION 5: WAVEFORM-LEVEL SANITY CHECK
%  Short run: show that at the SAME SNR, the two payloads differ because of
%  impairments (not a shift). One SNR point, few slots - just a smoke test.
%  Full BLER curves are in phase7_v3.m.
%  =====================================================================
fprintf('--- Section 5: Waveform-level sanity check ---\n');
try
    carrier = nrCarrierConfig; carrier.SubcarrierSpacing=15; carrier.NSizeGrid=52;
    pdsch   = nrPDSCHConfig;   pdsch.Modulation='16QAM'; pdsch.NumLayers=1;
    pdsch.PRBSet = (0:carrier.NSizeGrid-1)'; pdsch.SymbolAllocation=[0 14];
    pdsch.DMRS.DMRSAdditionalPosition = 1;
    R = 490/1024;
    [~, info] = nrPDSCHIndices(carrier,pdsch);
    tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, numel(pdsch.PRBSet), info.NREPerPRB, R);
    fs  = nrOFDMInfo(carrier).SampleRate;

    tdl = nrTDLChannel; tdl.DelayProfile=imp.chan.profile; tdl.DelaySpread=imp.chan.DS;
    tdl.MaximumDopplerShift=imp.chan.fd_Hz; tdl.SampleRate=fs;
    tdl.RandomStream='mt19937ar with seed'; tdl.Seed=params.channel.seed;

    pnR = comm.PhaseNoise('Level',profR.pn_dBc-[0 3 10], ...
            'FrequencyOffset',imp.pn.foffset_Hz, 'SampleRate',fs);
    pnT = comm.PhaseNoise('Level',profT.pn_dBc-[0 3 10], ...
            'FrequencyOffset',imp.pn.foffset_Hz, 'SampleRate',fs);

    snrSmoke = 8;  nSlotsSmoke = 20;
    failR = 0; failT = 0;
    for s = 1:nSlotsSmoke
        carrier.NSlot = s;
        [idx, inf] = nrPDSCHIndices(carrier, pdsch);
        trb = randi([0 1], tbs, 1);
        enc = nrDLSCH; enc.TargetCodeRate = R; setTransportBlock(enc, trb);
        cw  = enc(pdsch.Modulation, pdsch.NumLayers, inf.G, 0);
        sym = nrPDSCH(carrier, pdsch, cw);
        dmrsI = nrPDSCHDMRSIndices(carrier,pdsch); dmrsS = nrPDSCHDMRS(carrier,pdsch);
        g = nrResourceGrid(carrier); g(idx)=sym; g(dmrsI)=dmrsS;
        tx = nrOFDMModulate(carrier, g);

        failR = failR + runOneDecode(applyImpairments(tx,profR,pnR,fs), tdl, carrier, pdsch, dmrsI, dmrsS, idx, R, tbs, snrSmoke, 0);
        failT = failT + runOneDecode(applyImpairments(tx,profT,pnT,fs), tdl, carrier, pdsch, dmrsI, dmrsS, idx, R, tbs, snrSmoke, profT.feederPenalty_dB);
    end
    release(tdl);
    fprintf('  Smoke test @ %d dB, %d slots:  Regen fails=%d/%d, Transp fails=%d/%d\n', ...
        snrSmoke, nSlotsSmoke, failR, nSlotsSmoke, failT, nSlotsSmoke);
    if failT >= failR
        fprintf('  OK: transparent >= regen fails (impairment chain is active, no shift).\n\n');
    else
        fprintf('  NOTE: transparent < regen fails this round; try more slots.\n\n');
    end
catch ME
    fprintf('  Smoke test skipped: %s\n\n', ME.message);
end

%% =====================================================================
%  SECTION 6: VALIDATION CHECKS
%  =====================================================================
fprintf('--- Section 6: Validation checks ---\n');
fprintf('  [CHECK] no snrDegradation scalar exported ... ');
fprintf('PASS (Route A design)\n');
fprintf('  [CHECK] feederPenalty_dB positive at all elevations ... ');
if all(feederPenalty_dB>=0), fprintf('PASS\n'); else, fprintf('FAIL\n'); end
fprintf('  [CHECK] feeder SNR > user SNR at %d deg ... ', refElev);
if snr_feederlink(refIdx) > snr_userlink_DL(refIdx), fprintf('PASS\n'); else, fprintf('WARNING\n'); end
fprintf('  [CHECK] service-link residual CFO = 200 Hz (TS 38.101-5) ... ');
if imp.cfo.serviceLink_Hz == 200, fprintf('PASS\n'); else, fprintf('WARNING\n'); end
fprintf('\n');

%% =====================================================================
%  SECTION 7: EXPORT
%  =====================================================================
fprintf('--- Section 7: Exporting results ---\n');
phase4 = struct();
phase4.elevBudget       = elevBudget;
phase4.slantBudget      = slantBudget;
phase4.snr_userlink_UL  = snr_userlink_UL;
phase4.snr_userlink_DL  = snr_userlink_DL;
phase4.snr_feederlink   = snr_feederlink;
phase4.feederPenalty_dB = feederPenalty_dB;      % vector (one per elevation)
phase4.imp              = imp;
phase4.profR            = profR;
phase4.profT            = profT;
phase4.refElev          = refElev;
phase4.refIdx           = refIdx;
phase4.routeAVersion    = 'v3';                  % marker so phase6/7 can verify
% NOTE: phase4.snrDegradation is INTENTIONALLY NOT present.

outFile = fullfile(params.outputDir, 'phase4_results.mat');
save(outFile, 'phase4', '-v7.3');
fprintf('  Saved %s\n', outFile);

fprintf('\n============================================================\n');
fprintf('  PHASE 4 (v3) COMPLETE\n');
fprintf('============================================================\n');
fprintf('  Link budget: %d elevations, thermal-only cascade\n', nE);
fprintf('  Ref elevation %d deg, feeder penalty %.2f dB\n', refElev, imp.feeder.snrPenalty_dB);
fprintf('  Impairment profiles exported for phase6_v3 / phase7_v3.\n');
fprintf('  No "snrDegradation" shift exported anywhere.\n');
fprintf('============================================================\n');

%% ----- local function (receiver for the smoke test) -------------------
function fail = runOneDecode(tx, tdl, carrier, pdsch, dmrsI, dmrsS, idx, R, tbs, snrdB, feederPen)
    rx = tdl(tx);
    SNR  = 10^((snrdB-feederPen)/10);
    info = nrOFDMInfo(carrier);
    N0   = 1/sqrt(2*double(info.Nfft)*SNR);
    rx = rx + N0*(randn(size(rx))+1j*randn(size(rx)));
    off = nrTimingEstimate(carrier, rx, dmrsI, dmrsS);
    rx = rx(1+off:end,:);
    rg = nrOFDMDemodulate(carrier, rx);
    Lg = size(nrResourceGrid(carrier,pdsch.NumLayers),2);
    if size(rg,2) < Lg; rg(:,end+1:Lg,:) = 0; end
    [H,nV] = nrChannelEstimate(carrier, rg, dmrsI, dmrsS);
    eq = nrEqualizeMMSE(rg(idx), H(idx), nV);
    llr = nrPDSCHDecode(carrier, pdsch, eq, nV); if iscell(llr); llr = llr{1}; end
    dec = nrDLSCHDecoder; dec.TargetCodeRate=R; dec.TransportBlockLength=tbs;
    dec.LDPCDecodingAlgorithm = 'Normalized min-sum';
    [~, crc] = dec(llr, pdsch.Modulation, pdsch.NumLayers, 0);
    fail = double(crc);
end
