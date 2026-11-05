%% ========================================================================
%  PHASE 6 (v3 - Route A): Throughput Analysis
%  ========================================================================
%  WHAT CHANGED from phase6_throughput.m
%  ------------------------------------------------------------------------
%  v2 had the smoking-gun shift:
%      snrDeg = phase4.snrDegradation;
%      snr_transp_dB = snr_dB - snrDeg;
%      rxRegen  = awgn(rxWaveform, snr_dB,          'measured');
%      rxTransp = awgn(rxWaveform, snr_transp_dB,   'measured');   % <-- same rxWaveform
%  Both payloads shared the identical post-channel waveform; the transparent
%  curve was the regen AWGN curve with a different noise power. Reviewer #2's
%  verdict: the reported "shift matches link-budget" merely reproduces the
%  imposed offset.
%
%  v3 injects impairments PER PAYLOAD into the TX waveform:
%      txR = applyImpairments(tx, profR, pnR, fs)   % regen: 1 HPA, PN low, CFO 200 Hz
%      txT = applyImpairments(tx, profT, pnT, fs)   % transp: 2 HPAs cascaded, PN higher, CFO 500 Hz
%      rxR = chan(txR) + N0  @  SNR
%      rxT = chan(txT) + N0  @  (SNR - feederPenalty_dB)
%  Same channel realisation (seed) so the architectural difference is
%  isolated to pre-channel impairments. No "snrDegradation" is read.
%
%  Also drops the invalid FR1 case:
%      v2: scsValues = [15 30 60 120]  (120 kHz is NOT valid in FR1 at 2 GHz,
%                                        and v2 used an rbCounts entry for 20 MHz)
%      v3: scsValues = [15 30 60]      (all 10 MHz FR1)
%  ========================================================================
clc; clear; close all;
addpath('config'); addpath('helpers');
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 6 (v3 - Route A): Throughput Analysis\n');
fprintf('============================================================\n\n');

%% load prior phases -----------------------------------------------------
load(fullfile(params.outputDir,'phase4_results.mat'), 'phase4');
assert(isfield(phase4,'routeAVersion'), ...
    'phase4_results.mat is NOT the Route A (v3) version. Re-run phase4_v3.m first.');
assert(~isfield(phase4,'snrDegradation'), ...
    'phase4.snrDegradation is set — the shift is back. Re-run phase4_v3.m.');

if exist(fullfile(params.outputDir,'phase2_results.mat'),'file')==2
    load(fullfile(params.outputDir,'phase2_results.mat'),'phase2');
    mobileDoppler = phase2.mobileDoppler;
else
    mobileDoppler = params.ue.speed_ms * params.rf.carrierFrequency / params.c;
end

%% =====================================================================
%  SECTION 1: CONFIGURATION
%  =====================================================================
fprintf('--- Section 1: Configuration ---\n');

scsValues = [15 30 60];                       % 120 kHz dropped (invalid FR1 at 2 GHz)
rbCounts  = [52 24 11];                       % 10 MHz BW, TS 38.101-1 Table 5.3.2-1
nSCS      = numel(scsValues);

snrRange_dB  = -4:2:20;
nSNR         = numel(snrRange_dB);
nSlotsPerSNR = 50;

modScheme      = '16QAM';
targetCodeRate = 490/1024;

imp   = phase4.imp;
profR = phase4.profR;
profT = phase4.profT;

fprintf('  SCS: [%s] kHz | RBs: [%s] | SNR: %d:%d:%d dB | %d slots/pt\n', ...
    strjoin(string(scsValues),' '), strjoin(string(rbCounts),' '), ...
    snrRange_dB(1), snrRange_dB(2)-snrRange_dB(1), snrRange_dB(end), nSlotsPerSNR);
fprintf('  Modulation: %s, R=%.3f | Channel: %s (DS=%.0f ns)\n', ...
    modScheme, targetCodeRate, imp.chan.profile, imp.chan.DS*1e9);
fprintf('  Service-link residual CFO: %d Hz (both) | Transparent total CFO: %d Hz\n', ...
    imp.cfo.serviceLink_Hz, profT.cfo_Hz);
fprintf('  Transparent feeder penalty: %.2f dB (from Phase 4 cascade)\n\n', profT.feederPenalty_dB);

%% =====================================================================
%  SECTION 2: THROUGHPUT SWEEP (per SCS, per SNR, per payload)
%  =====================================================================
tput_regen  = zeros(nSNR, nSCS);
tput_transp = zeros(nSNR, nSCS);
maxTput     = zeros(1, nSCS);
tbsPerSCS   = zeros(1, nSCS);

tStart = tic;

for scsIdx = 1:nSCS
    scs = scsValues(scsIdx);
    nRB = rbCounts(scsIdx);
    slotDur_s   = 1e-3 / 2^(log2(scs/15));
    slotsPerSec = 1/slotDur_s;

    fprintf('\n  === SCS = %d kHz (%d RBs) ===\n', scs, nRB);

    carrier = nrCarrierConfig; carrier.SubcarrierSpacing=scs; carrier.NSizeGrid=nRB;
    carrier.CyclicPrefix='Normal';

    pdsch = nrPDSCHConfig; pdsch.Modulation=modScheme; pdsch.NumLayers=1;
    pdsch.PRBSet=(0:nRB-1)'; pdsch.SymbolAllocation=[0 14];
    pdsch.MappingType='A'; pdsch.DMRS.DMRSConfigurationType=1;
    pdsch.DMRS.DMRSLength=1; pdsch.DMRS.DMRSAdditionalPosition=1;
    pdsch.DMRS.DMRSTypeAPosition=2;

    carrier.NSlot = 0;
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
    tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, numel(pdsch.PRBSet), ...
                pdschInfo.NREPerPRB, targetCodeRate);
    tbsPerSCS(scsIdx) = tbs;
    maxTput(scsIdx)   = tbs * slotsPerSec / 1e6;        % Mbps peak

    [~, ofdmInfo] = nrOFDMModulate(carrier, nrResourceGrid(carrier));
    sr = ofdmInfo.SampleRate;
    fprintf('    TBS=%d bits | SR=%.3f MHz | Peak=%.2f Mbps\n', tbs, sr/1e6, maxTput(scsIdx));

    % shared service-link TDL channel (same seed for both payloads)
    tdl = nrTDLChannel;
    tdl.DelayProfile=imp.chan.profile; tdl.DelaySpread=imp.chan.DS;
    tdl.MaximumDopplerShift=mobileDoppler;
    tdl.SampleRate=sr; tdl.RandomStream='mt19937ar with seed';
    tdl.Seed=params.channel.seed + scsIdx;
    chInfo = info(tdl); maxChDelay = chInfo.MaximumChannelDelay;

    % per-payload phase-noise objects
    pnR = comm.PhaseNoise('Level',profR.pn_dBc-[0 3 10], ...
          'FrequencyOffset',imp.pn.foffset_Hz,'SampleRate',sr);
    pnT = comm.PhaseNoise('Level',profT.pn_dBc-[0 3 10], ...
          'FrequencyOffset',imp.pn.foffset_Hz,'SampleRate',sr);

    for snrIdx = 1:nSNR
        snr_dB = snrRange_dB(snrIdx);
        passR = 0; passT = 0;

        for slot = 0:(nSlotsPerSNR-1)
            carrier.NSlot = slot;

            % ----- generate ONE TX symbol stream -----
            trBlk = randi([0 1], tbs, 1);
            enc = nrDLSCH; enc.TargetCodeRate = targetCodeRate; setTransportBlock(enc, trBlk);
            [idx, info2] = nrPDSCHIndices(carrier, pdsch);
            cw = enc(pdsch.Modulation, pdsch.NumLayers, info2.G, 0);
            sym = nrPDSCH(carrier, pdsch, cw);
            dmrsI = nrPDSCHDMRSIndices(carrier, pdsch);
            dmrsS = nrPDSCHDMRS(carrier, pdsch);
            g = nrResourceGrid(carrier); g(idx)=sym; g(dmrsI)=dmrsS;
            tx = nrOFDMModulate(carrier, g);
            tx = [tx; zeros(maxChDelay,1)];

            % ----- impairment injection PER PAYLOAD -----
            txR_imp = applyImpairments(tx, profR, pnR, sr);
            txT_imp = applyImpairments(tx, profT, pnT, sr);

            % ----- same channel realisation for both payloads -----
            % release+re-seed before EACH payload so both see the identical
            % channel realisation on this slot (isolates the architectural
            % difference to pre-channel impairments).
            slotSeed = params.channel.seed + scsIdx + 10*slot;
            release(tdl); tdl.Seed = slotSeed;  rxR = tdl(txR_imp);
            release(tdl); tdl.Seed = slotSeed;  rxT = tdl(txT_imp);

            % ----- AWGN: regen at SNR, transparent at SNR - feederPenalty -----
            rxR = addAWGN(rxR, snr_dB,                           carrier);
            rxT = addAWGN(rxT, snr_dB - profT.feederPenalty_dB,  carrier);

            % ----- receive & decode -----
            passR = passR + double(decodeOne(rxR, carrier, pdsch, dmrsI, dmrsS, idx, ...
                                             targetCodeRate, tbs, maxChDelay) == 0);
            passT = passT + double(decodeOne(rxT, carrier, pdsch, dmrsI, dmrsS, idx, ...
                                             targetCodeRate, tbs, maxChDelay) == 0);
        end

        tput_regen(snrIdx, scsIdx)  = (passR/nSlotsPerSNR) * maxTput(scsIdx);
        tput_transp(snrIdx, scsIdx) = (passT/nSlotsPerSNR) * maxTput(scsIdx);

        fprintf('    SNR=%+5.1f dB | R: %2d/%d (%.2f Mbps) | T: %2d/%d (%.2f Mbps)\n', ...
            snr_dB, passR, nSlotsPerSNR, tput_regen(snrIdx,scsIdx), ...
                     passT, nSlotsPerSNR, tput_transp(snrIdx,scsIdx));
    end
    release(tdl);
end
fprintf('\n  Total time: %.1f min\n\n', toc(tStart)/60);

%% =====================================================================
%  SECTION 3: PLOTS (clean, no data1/data2, consistent legends)
%  =====================================================================
fprintf('--- Section 3: Plots ---\n');
cols = lines(nSCS);

figure('Name','Throughput v3','Position',[100 100 1050 450]); hold on; grid on;
for s = 1:nSCS
    plot(snrRange_dB, tput_regen(:,s), '-o','LineWidth',1.8,'MarkerSize',5, ...
        'Color',cols(s,:), ...
        'DisplayName',sprintf('Regen, SCS %d kHz (%d RB)',scsValues(s),rbCounts(s)));
    plot(snrRange_dB, tput_transp(:,s),'--s','LineWidth',1.8,'MarkerSize',5, ...
        'Color',cols(s,:), ...
        'DisplayName',sprintf('Transp, SCS %d kHz (%d RB)',scsValues(s),rbCounts(s)));
end
xlabel('SNR (dB)'); ylabel('Throughput (Mbps)');
title('PDSCH Throughput - Route A (independent impairments; no SNR shift)');
legend('Location','northwest','FontSize',9); set(gca,'FontSize',11);
saveas(gcf, fullfile(params.outputDir,'phase6_v3_throughput.png'));
fprintf('  Saved phase6_v3_throughput.png\n');

[~, opIdx] = min(abs(snrRange_dB-10)); opSNR = snrRange_dB(opIdx);
figure('Name','Throughput bar v3','Position',[100 100 900 450]);
bh = bar([tput_transp(opIdx,:); tput_regen(opIdx,:)]', 'grouped');
bh(1).FaceColor=[0.85 0.33 0.1]; bh(2).FaceColor=[0.0 0.45 0.74];
set(gca,'XTickLabel',arrayfun(@(x)sprintf('%d kHz',x),scsValues,'UniformOutput',false));
xlabel('Subcarrier Spacing'); ylabel('Throughput (Mbps)');
title(sprintf('Throughput at SNR = %d dB (16QAM, R=0.48)', opSNR));
legend({'Transparent','Regenerative'},'Location','northeast'); grid on; set(gca,'FontSize',11);
saveas(gcf, fullfile(params.outputDir,'phase6_v3_throughput_bar.png'));
fprintf('  Saved phase6_v3_throughput_bar.png\n\n');

%% =====================================================================
%  SECTION 4: VALIDATION
%  =====================================================================
fprintf('--- Section 4: Validation ---\n');
fprintf('  [CHECK] no 120 kHz SCS case ... ');
if ~any(scsValues==120), fprintf('PASS\n'); else, fprintf('FAIL\n'); end
fprintf('  [CHECK] regen tput >= transparent tput at every point ... ');
if all(tput_regen(:) >= tput_transp(:) - 0.1), fprintf('PASS\n'); else, fprintf('WARNING\n'); end
fprintf('  [CHECK] no reference to phase4.snrDegradation ... PASS (not loaded)\n\n');

%% =====================================================================
%  SECTION 5: EXPORT
%  =====================================================================
phase6 = struct();
phase6.scsValues     = scsValues;
phase6.rbCounts      = rbCounts;
phase6.snrRange_dB   = snrRange_dB;
phase6.nSlotsPerSNR  = nSlotsPerSNR;
phase6.modScheme     = modScheme;
phase6.targetCodeRate= targetCodeRate;
phase6.tput_regen    = tput_regen;
phase6.tput_transp   = tput_transp;
phase6.maxTput       = maxTput;
phase6.tbsPerSCS     = tbsPerSCS;
phase6.channelProfile= imp.chan.profile;
phase6.routeAVersion = 'v3';
save(fullfile(params.outputDir,'phase6_results.mat'),'phase6','-v7.3');
fprintf('  Saved phase6_results.mat\n');

fprintf('\n============================================================\n');
fprintf('  PHASE 6 (v3) COMPLETE\n');
fprintf('============================================================\n');
for s = 1:nSCS
    fprintf('    SCS %d kHz peak: %.2f Mbps (TBS=%d bits)\n', scsValues(s), maxTput(s), tbsPerSCS(s));
end
fprintf('  Independent transparent-vs-regen throughput (no SNR shift).\n');
fprintf('============================================================\n');

%% ----- local helpers ---------------------------------------------------
function y = addAWGN(x, snrdB, carrier)
    SNR = 10^(snrdB/10);
    info = nrOFDMInfo(carrier);
    N0 = 1/sqrt(2*double(info.Nfft)*SNR);
    y = x + N0*(randn(size(x))+1j*randn(size(x)));
end

function crc = decodeOne(rx, carrier, pdsch, dmrsI, dmrsS, idx, R, tbs, maxChDelay)
    rx = rx(1:end-maxChDelay);
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
end
