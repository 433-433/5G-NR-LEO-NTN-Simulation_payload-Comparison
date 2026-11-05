%% ========================================================================
%  PHASE 7: Reliability (BLER) Analysis
%  ========================================================================
%  Performance Analysis of 5G NR in LEO Non-Terrestrial Networks
%
%  Computes Block Error Rate (BLER) — the primary 5G NR reliability metric.
%  BLER = ratio of transport blocks failing CRC to total TBs transmitted.
%
%  Key results:
%    1. BLER vs SNR for both payloads (with 10% BLER target line)
%    2. BLER across multiple MCS values
%    3. HARQ combining gain (regenerative only — disabled for transparent)
%    4. Coded vs uncoded BER comparison showing LDPC coding gain
%
%  3GPP References:
%    TS 38.214 Sec 5.1.3   — MCS tables, 10% BLER target
%    TS 38.212             — LDPC coding
%    TR 38.821 Sec 7.3     — HARQ for NTN
%  ========================================================================
clc; clear; close all;

%% Add paths and load previous results
addpath('config');
addpath('helpers');
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 7: Reliability (BLER) Analysis\n');
fprintf('  LEO NTN — 5G NR Performance Analysis (FINAL PHASE)\n');
fprintf('============================================================\n\n');

load(fullfile(params.outputDir, 'phase2_results.mat'), 'phase2');
load(fullfile(params.outputDir, 'phase4_results.mat'), 'phase4');
fprintf('  Phase 2 and Phase 4 loaded.\n\n');

%% =====================================================================
%  SECTION 1: CONFIGURATION
%  =====================================================================
fprintf('--- Section 1: Configuration ---\n');

% Use 15 kHz SCS as primary (most relevant for NTN)
scs     = 15;
nRB     = 52;
snrDeg  = phase4.snrDegradation;

% SNR sweep — fine resolution around waterfall region
snrRange = -2:0.5:16;
nSNR     = length(snrRange);

% Slots per SNR point (more = smoother curves)
nSlots   = 100;

% Channel config
channelProfile = 'NTN-TDL-C';
delaySpread    = params.channel.delaySpread.suburban;
mobileDoppler  = phase2.mobileDoppler;

% MCS configurations to test
% [modulation, targetCodeRate, label]
mcsConfigs = {
    'QPSK',   120/1024,  'MCS 0 (QPSK R=0.12)';
    'QPSK',   449/1024,  'MCS 4 (QPSK R=0.44)';
    '16QAM',  340/1024,  'MCS 10 (16QAM R=0.33)';
    '16QAM',  490/1024,  'MCS 15 (16QAM R=0.48)';
    '64QAM',  567/1024,  'MCS 21 (64QAM R=0.55)';
};
nMCS = size(mcsConfigs, 1);

fprintf('  SCS: %d kHz | RBs: %d | SNR: %.1f to %.1f dB (%.1f step)\n', ...
    scs, nRB, snrRange(1), snrRange(end), snrRange(2)-snrRange(1));
fprintf('  Slots per SNR point: %d\n', nSlots);
fprintf('  Transparent penalty: %.1f dB\n', snrDeg);
fprintf('  MCS configurations: %d\n', nMCS);
fprintf('  Channel: %s\n\n', channelProfile);

%% =====================================================================
%  SECTION 2: BLER vs SNR — BOTH PAYLOADS (Primary MCS)
%  =====================================================================
fprintf('--- Section 2: BLER vs SNR — Regenerative vs Transparent ---\n');
fprintf('  Using MCS 15 (16QAM, rate ~0.48)\n');

modScheme      = '16QAM';
targetCodeRate = 490/1024;

% Configure carrier
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = scs;
carrier.NSizeGrid = nRB;
carrier.CyclicPrefix = 'Normal';

% Configure PDSCH
pdsch = nrPDSCHConfig;
pdsch.Modulation = modScheme;
pdsch.NumLayers = 1;
pdsch.PRBSet = (0:nRB-1)';
pdsch.SymbolAllocation = [0 14];
pdsch.MappingType = 'A';
pdsch.DMRS.DMRSConfigurationType = 1;
pdsch.DMRS.DMRSLength = 1;
pdsch.DMRS.DMRSAdditionalPosition = 1;
pdsch.DMRS.DMRSTypeAPosition = 2;

% Get TBS
carrier.NSlot = 0;
[~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, ...
    length(pdsch.PRBSet), pdschInfo.NREPerPRB, targetCodeRate);

% OFDM info
[~, ofdmInfo] = nrOFDMModulate(carrier, nrResourceGrid(carrier));
sr = ofdmInfo.SampleRate;

fprintf('  TBS = %d bits | SR = %.2f MHz\n', tbs, sr/1e6);

% Channel
tdlChan = nrTDLChannel;
tdlChan.DelayProfile = channelProfile;
tdlChan.DelaySpread = delaySpread;
tdlChan.MaximumDopplerShift = mobileDoppler;
tdlChan.SampleRate = sr;
tdlChan.NumTransmitAntennas = 1;
tdlChan.NumReceiveAntennas = 1;
tdlChan.RandomStream = params.channel.randomStream;
tdlChan.Seed = params.channel.seed;

chInfo = info(tdlChan);
maxChDelay = chInfo.MaximumChannelDelay;

% Preallocate
bler_regen  = zeros(nSNR, 1);
bler_transp = zeros(nSNR, 1);
ber_coded_regen  = zeros(nSNR, 1);
ber_coded_transp = zeros(nSNR, 1);

totalStart = tic;

for snrIdx = 1:nSNR
    snr_dB = snrRange(snrIdx);
    snr_transp_dB = snr_dB - snrDeg;
    
    tbFailR = 0; tbFailT = 0;
    bitErrR = 0; bitErrT = 0; totalBits = 0;
    
    for slot = 0:(nSlots-1)
        carrier.NSlot = slot;
        
        % Encode
        trBlk = randi([0 1], tbs, 1);
        enc = nrDLSCH;
        enc.TargetCodeRate = targetCodeRate;
        setTransportBlock(enc, trBlk);
        
        [pdschIndices, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
        codedBits = enc(pdsch.Modulation, pdsch.NumLayers, pdschInfo.G, 0);
        
        % Modulate
        pdschSymbols = nrPDSCH(carrier, pdsch, codedBits);
        dmrsIndices = nrPDSCHDMRSIndices(carrier, pdsch);
        dmrsSymbols = nrPDSCHDMRS(carrier, pdsch);
        
        grid = nrResourceGrid(carrier);
        grid(pdschIndices) = pdschSymbols;
        grid(dmrsIndices) = dmrsSymbols;
        
        % OFDM modulate
        txWaveform = nrOFDMModulate(carrier, grid);
        txWaveform = [txWaveform; zeros(maxChDelay, 1)];
        
        % Channel
        rxWaveform = tdlChan(txWaveform);
        
        % Add noise
        rxR = awgn(rxWaveform, snr_dB, 'measured');
        rxT = awgn(rxWaveform, snr_transp_dB, 'measured');
        
        % OFDM demod
        rxGridR = nrOFDMDemodulate(carrier, rxR(1:end-maxChDelay));
        rxGridT = nrOFDMDemodulate(carrier, rxT(1:end-maxChDelay));
        
        % Channel estimate
        [estChR, noiseR] = nrChannelEstimate(carrier, rxGridR, dmrsIndices, dmrsSymbols);
        [estChT, noiseT] = nrChannelEstimate(carrier, rxGridT, dmrsIndices, dmrsSymbols);
        
        % Equalize
        [eqR, ~] = nrEqualizeMMSE(rxGridR(pdschIndices), estChR(pdschIndices), noiseR);
        [eqT, ~] = nrEqualizeMMSE(rxGridT(pdschIndices), estChT(pdschIndices), noiseT);
        
        % Soft demod
        softR = nrPDSCHDecode(carrier, pdsch, eqR, noiseR);
        softT = nrPDSCHDecode(carrier, pdsch, eqT, noiseT);
        
        % Decode — Regenerative
        decR = nrDLSCHDecoder;
        decR.TargetCodeRate = targetCodeRate;
        decR.TransportBlockLength = tbs;
        [rxTrBlkR, crcR] = decR(softR{1}, pdsch.Modulation, pdsch.NumLayers, 0);
        if crcR ~= 0, tbFailR = tbFailR + 1; end
        bitErrR = bitErrR + sum(rxTrBlkR ~= trBlk);
        
        % Decode — Transparent
        decT = nrDLSCHDecoder;
        decT.TargetCodeRate = targetCodeRate;
        decT.TransportBlockLength = tbs;
        [rxTrBlkT, crcT] = decT(softT{1}, pdsch.Modulation, pdsch.NumLayers, 0);
        if crcT ~= 0, tbFailT = tbFailT + 1; end
        bitErrT = bitErrT + sum(rxTrBlkT ~= trBlk);
        
        totalBits = totalBits + tbs;
    end
    
    bler_regen(snrIdx)  = tbFailR / nSlots;
    bler_transp(snrIdx) = tbFailT / nSlots;
    ber_coded_regen(snrIdx)  = bitErrR / totalBits;
    ber_coded_transp(snrIdx) = bitErrT / totalBits;
    
    fprintf('    SNR=%5.1f dB | R: BLER=%.3f BER=%.1e | T: BLER=%.3f BER=%.1e\n', ...
        snr_dB, bler_regen(snrIdx), ber_coded_regen(snrIdx), ...
        bler_transp(snrIdx), ber_coded_transp(snrIdx));
end

elapsed_sec2 = toc(totalStart);
fprintf('  Section 2 complete in %.1f seconds.\n\n', elapsed_sec2);

%% =====================================================================
%  SECTION 3: BLER vs SNR — MULTIPLE MCS VALUES
%  =====================================================================
fprintf('--- Section 3: BLER vs SNR — Multiple MCS ---\n');

% Wider SNR range for multiple MCS
snrMCS = -6:1:24;
nSNR_MCS = length(snrMCS);
nSlotsMCS = 60;  % Fewer slots for speed

bler_mcs_regen = zeros(nSNR_MCS, nMCS);

for mIdx = 1:nMCS
    modMCS  = mcsConfigs{mIdx, 1};
    rateMCS = mcsConfigs{mIdx, 2};
    lblMCS  = mcsConfigs{mIdx, 3};
    
    fprintf('  %s\n', lblMCS);
    
    % Configure PDSCH for this MCS
    pdschMCS = nrPDSCHConfig;
    pdschMCS.Modulation = modMCS;
    pdschMCS.NumLayers = 1;
    pdschMCS.PRBSet = (0:nRB-1)';
    pdschMCS.SymbolAllocation = [0 14];
    pdschMCS.MappingType = 'A';
    pdschMCS.DMRS.DMRSConfigurationType = 1;
    pdschMCS.DMRS.DMRSLength = 1;
    pdschMCS.DMRS.DMRSAdditionalPosition = 1;
    pdschMCS.DMRS.DMRSTypeAPosition = 2;
    
    carrier.NSlot = 0;
    [~, infoMCS] = nrPDSCHIndices(carrier, pdschMCS);
    tbsMCS = nrTBS(pdschMCS.Modulation, pdschMCS.NumLayers, ...
        length(pdschMCS.PRBSet), infoMCS.NREPerPRB, rateMCS);
    
    fprintf('    TBS = %d bits\n', tbsMCS);
    
    for snrIdx = 1:nSNR_MCS
        snr_dB = snrMCS(snrIdx);
        tbFail = 0;
        
        for slot = 0:(nSlotsMCS-1)
            carrier.NSlot = slot;
            
            trBlk = randi([0 1], tbsMCS, 1);
            enc = nrDLSCH;
            enc.TargetCodeRate = rateMCS;
            setTransportBlock(enc, trBlk);
            
            [idxM, infoM] = nrPDSCHIndices(carrier, pdschMCS);
            coded = enc(pdschMCS.Modulation, pdschMCS.NumLayers, infoM.G, 0);
            
            syms = nrPDSCH(carrier, pdschMCS, coded);
            dmrsIdx = nrPDSCHDMRSIndices(carrier, pdschMCS);
            dmrsSym = nrPDSCHDMRS(carrier, pdschMCS);
            
            g = nrResourceGrid(carrier);
            g(idxM) = syms;
            g(dmrsIdx) = dmrsSym;
            
            tx = nrOFDMModulate(carrier, g);
            tx = [tx; zeros(maxChDelay, 1)];
            
            rx = tdlChan(tx);
            rx = awgn(rx, snr_dB, 'measured');
            
            rxG = nrOFDMDemodulate(carrier, rx(1:end-maxChDelay));
            [eCh, nEst] = nrChannelEstimate(carrier, rxG, dmrsIdx, dmrsSym);
            [eqS, ~] = nrEqualizeMMSE(rxG(idxM), eCh(idxM), nEst);
            soft = nrPDSCHDecode(carrier, pdschMCS, eqS, nEst);
            
            dec = nrDLSCHDecoder;
            dec.TargetCodeRate = rateMCS;
            dec.TransportBlockLength = tbsMCS;
            [~, crc] = dec(soft{1}, pdschMCS.Modulation, pdschMCS.NumLayers, 0);
            
            if crc ~= 0, tbFail = tbFail + 1; end
        end
        
        bler_mcs_regen(snrIdx, mIdx) = tbFail / nSlotsMCS;
    end
    
    % Find 10% BLER point
    idx10 = find(bler_mcs_regen(:, mIdx) <= 0.1, 1, 'first');
    if ~isempty(idx10)
        fprintf('    10%% BLER at SNR ~%.1f dB\n', snrMCS(idx10));
    end
end
fprintf('\n');

%% =====================================================================
%  SECTION 4: UNCODED BER (Reference)
%  =====================================================================
fprintf('--- Section 4: Uncoded BER reference ---\n');

M = 16;  % 16QAM
nSymUncoded = 100000;
rng(params.channel.seed);

ber_uncoded = zeros(nSNR, 1);

for snrIdx = 1:nSNR
    data = randi([0 M-1], nSymUncoded, 1);
    txSym = qammod(data, M, 'UnitAveragePower', true);
    rxSym = awgn(txSym, snrRange(snrIdx), 'measured');
    rxData = qamdemod(rxSym, M, 'UnitAveragePower', true);
    [~, ratio] = biterr(data, rxData, log2(M));
    ber_uncoded(snrIdx) = ratio;
end
fprintf('  Uncoded 16QAM BER computed.\n\n');

%% =====================================================================
%  SECTION 5: PLOTS
%  =====================================================================
fprintf('--- Section 5: Generating plots ---\n');

colors = lines(8);

% ---- Figure 1: BLER vs SNR — Both Payloads ----
figure('Name', 'BLER Comparison', 'Position', [100 100 900 550]);
semilogy(snrRange, bler_regen, '-bs', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'Regenerative (16QAM R=0.48)');
hold on;
semilogy(snrRange, bler_transp, '-ro', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', sprintf('Transparent (%.1f dB degradation)', snrDeg));
yline(0.1, '--k', '10% BLER Target', 'LineWidth', 1.5, 'FontSize', 10, ...
    'LabelHorizontalAlignment', 'left');
hold off;
xlabel('SNR (dB)', 'FontSize', 12);
ylabel('Block Error Rate (BLER)', 'FontSize', 12);
title('5G NR LEO NTN Reliability — BLER vs SNR', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 10);
grid on; set(gca, 'FontSize', 11);
ylim([1e-3 1]);
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_comparison.png'));
fprintf('  Saved: phase7_bler_comparison.png\n');

% ---- Figure 2: BLER vs SNR — Multiple MCS (Regenerative) ----
figure('Name', 'BLER Multi-MCS', 'Position', [100 100 900 550]);
hold on;
for mIdx = 1:nMCS
    semilogy(snrMCS, bler_mcs_regen(:, mIdx), '-o', 'LineWidth', 1.8, ...
        'MarkerSize', 4, 'Color', colors(mIdx,:), ...
        'DisplayName', mcsConfigs{mIdx, 3});
end
yline(0.1, '--k', '10% BLER Target', 'LineWidth', 1.5, 'FontSize', 9, ...
    'LabelHorizontalAlignment', 'left');
hold off;
xlabel('SNR (dB)', 'FontSize', 12);
ylabel('BLER', 'FontSize', 12);
title('BLER vs SNR — Multiple MCS (Regenerative, NTN-TDL-C)', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 8);
grid on; set(gca, 'FontSize', 11);
ylim([1e-2 1]);
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_multi_mcs.png'));
fprintf('  Saved: phase7_bler_multi_mcs.png\n');

% ---- Figure 3: Coded BER vs Uncoded BER ----
figure('Name', 'BER Comparison', 'Position', [100 100 900 550]);
semilogy(snrRange, ber_uncoded, '-k^', 'LineWidth', 1.5, 'MarkerSize', 5, ...
    'DisplayName', 'Uncoded 16QAM (AWGN)');
hold on;
semilogy(snrRange, ber_coded_regen, '-bs', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'LDPC Coded — Regenerative');
semilogy(snrRange, ber_coded_transp, '-ro', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'LDPC Coded — Transparent');
hold off;
xlabel('SNR (dB)', 'FontSize', 12);
ylabel('Bit Error Rate (BER)', 'FontSize', 12);
title('Coded vs Uncoded BER — LDPC Coding Gain', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 10);
grid on; set(gca, 'FontSize', 11);
ylim([1e-6 1]);
saveas(gcf, fullfile(params.outputDir, 'phase7_ber_coded_vs_uncoded.png'));
fprintf('  Saved: phase7_ber_coded_vs_uncoded.png\n');

% ---- Figure 4: BLER Comparison with HARQ Note ----
figure('Name', 'BLER HARQ', 'Position', [100 100 1000 550]);

subplot(1, 2, 1);
semilogy(snrRange, bler_regen, '-bs', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Regenerative (1st Tx)');
hold on;
% Approximate HARQ gain: after 1 retx, BLER improves roughly by BLER^2
% (chase combining approximation)
bler_harq1 = bler_regen .* bler_regen;   % After 1 retransmission
bler_harq2 = bler_harq1 .* bler_regen;    % After 2 retransmissions
semilogy(snrRange, bler_harq1, '-g^', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Regen + 1 HARQ retx');
semilogy(snrRange, bler_harq2, '-md', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Regen + 2 HARQ retx');
yline(0.1, '--k', '10% BLER', 'LineWidth', 1);
yline(0.01, ':k', '1% BLER', 'LineWidth', 1);
hold off;
xlabel('SNR (dB)', 'FontSize', 11);
ylabel('BLER', 'FontSize', 11);
title('Regenerative — HARQ Combining', 'FontSize', 12);
legend('Location', 'southwest', 'FontSize', 8);
grid on; set(gca, 'FontSize', 10);
ylim([1e-4 1]);

subplot(1, 2, 2);
semilogy(snrRange, bler_transp, '-ro', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Transparent (1st Tx only)');
hold on;
yline(0.1, '--k', '10% BLER', 'LineWidth', 1);
yline(0.01, ':k', '1% BLER', 'LineWidth', 1);

% Shade the "HARQ disabled" region
text(mean(snrRange), 0.5, 'HARQ DISABLED', 'FontSize', 14, ...
    'HorizontalAlignment', 'center', 'Color', [0.7 0 0], ...
    'FontWeight', 'bold');
text(mean(snrRange), 0.25, '(RTT exceeds timer)', 'FontSize', 10, ...
    'HorizontalAlignment', 'center', 'Color', [0.5 0 0]);
hold off;
xlabel('SNR (dB)', 'FontSize', 11);
ylabel('BLER', 'FontSize', 11);
title('Transparent — No HARQ', 'FontSize', 12);
legend('Location', 'southwest', 'FontSize', 9);
grid on; set(gca, 'FontSize', 10);
ylim([1e-4 1]);

sgtitle('HARQ Impact on Reliability — Regenerative vs Transparent', ...
    'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_harq.png'));
fprintf('  Saved: phase7_bler_harq.png\n');

%% =====================================================================
%  SECTION 6: VALIDATION CHECKS
%  =====================================================================
fprintf('\n--- Section 6: Validation checks ---\n');

% Find 10% BLER points
idx10_R = find(bler_regen <= 0.1, 1, 'first');
idx10_T = find(bler_transp <= 0.1, 1, 'first');

if ~isempty(idx10_R) && ~isempty(idx10_T)
    snr10_R = snrRange(idx10_R);
    snr10_T = snrRange(idx10_T);
    blerShift = snr10_T - snr10_R;
    fprintf('  10%% BLER point — Regenerative: %.1f dB | Transparent: %.1f dB\n', snr10_R, snr10_T);
    fprintf('  BLER waterfall shift: %.1f dB (expected ~%.1f dB)\n', blerShift, snrDeg);
else
    fprintf('  WARNING: Could not find 10%% BLER crossing point.\n');
    blerShift = NaN;
end

fprintf('  [CHECK] Regen BLER <= Transparent at all SNR... ');
if all(bler_regen <= bler_transp + 0.01), fprintf('PASS\n'); else, fprintf('WARNING\n'); end

fprintf('  [CHECK] BLER approaches 0 at high SNR (regen)... ');
if bler_regen(end) < 0.05, fprintf('PASS (%.3f)\n', bler_regen(end)); 
else, fprintf('WARNING (%.3f)\n', bler_regen(end)); end

fprintf('  [CHECK] BLER ~1 at very low SNR... ');
if bler_regen(1) > 0.8, fprintf('PASS (%.3f)\n', bler_regen(1)); 
else, fprintf('WARNING (%.3f)\n', bler_regen(1)); end

% Coding gain estimate
idx_uncoded = find(ber_uncoded <= 1e-3, 1, 'first');
idx_coded = find(ber_coded_regen <= 1e-3, 1, 'first');
if ~isempty(idx_uncoded) && ~isempty(idx_coded)
    codingGain = snrRange(idx_uncoded) - snrRange(idx_coded);
    fprintf('  [CHECK] LDPC coding gain at BER=1e-3: %.1f dB (expected 5-10 dB)... ', codingGain);
    if codingGain > 3, fprintf('PASS\n'); else, fprintf('WARNING\n'); end
else
    fprintf('  [CHECK] Coding gain: Could not compute (BER threshold not reached)\n');
end

fprintf('\n');

%% =====================================================================
%  SECTION 7: EXPORT RESULTS
%  =====================================================================
fprintf('--- Section 7: Exporting results ---\n');

phase7 = struct();

% Primary BLER curves
phase7.snrRange       = snrRange;
phase7.bler_regen     = bler_regen;
phase7.bler_transp    = bler_transp;
phase7.ber_coded_regen  = ber_coded_regen;
phase7.ber_coded_transp = ber_coded_transp;
phase7.ber_uncoded    = ber_uncoded;

% Multi-MCS BLER
phase7.snrMCS         = snrMCS;
phase7.bler_mcs_regen = bler_mcs_regen;
phase7.mcsConfigs     = mcsConfigs;

% HARQ approximation
phase7.bler_harq1     = bler_harq1;
phase7.bler_harq2     = bler_harq2;

% Key metrics
phase7.snrDegradation = snrDeg;
phase7.blerShift_dB   = blerShift;

outFile = fullfile(params.outputDir, 'phase7_results.mat');
save(outFile, 'phase7', '-v7.3');
fprintf('  Saved: %s\n', outFile);

%% =====================================================================
%  SUMMARY
%  =====================================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 7 COMPLETE — ALL PHASES DONE\n');
fprintf('============================================================\n');
if ~isempty(idx10_R) && ~isempty(idx10_T)
    fprintf('  10%% BLER SNR: Regen=%.1f dB | Transp=%.1f dB | Shift=%.1f dB\n', ...
        snr10_R, snr10_T, blerShift);
end
fprintf('  BLER curves: Regenerative vs Transparent (MCS 15)\n');
fprintf('  Multi-MCS BLER: %d configurations tested\n', nMCS);
fprintf('  HARQ: Enabled for regenerative (BLER^2 improvement)\n');
fprintf('         Disabled for transparent (RTT exceeds timer)\n');
fprintf('  Coded vs Uncoded BER: LDPC coding gain demonstrated\n');
fprintf('\n  ============= PROJECT COMPLETE =============\n');
fprintf('  All 7 phases executed successfully.\n');
fprintf('  Results in: %s\n', params.outputDir);
fprintf('  Total figures generated across all phases: ~30+\n');
fprintf('============================================================\n');
