%% ========================================================================
%  PHASE 7: Reliability (BLER) Analysis (v2 — Dual Environment)
%  ========================================================================
%  Performance Analysis of 5G NR in LEO Non-Terrestrial Networks
%
%  UPDATES from v1:
%    - 300 slots per SNR point (smoother BLER curves, floor ~0.003)
%    - DUAL environment: Suburban (NTN-TDL-C) + Rural (NTN-TDL-D)
%    - Environment comparison plot added
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
fprintf('  PHASE 7: Reliability (BLER) Analysis (v2 — Dual Env)\n');
fprintf('  LEO NTN — 5G NR Performance Analysis (FINAL PHASE)\n');
fprintf('============================================================\n\n');

load(fullfile(params.outputDir, 'phase2_results.mat'), 'phase2');
load(fullfile(params.outputDir, 'phase4_results.mat'), 'phase4');
fprintf('  Phase 2 and Phase 4 loaded.\n\n');

%% =====================================================================
%  SECTION 1: CONFIGURATION
%  =====================================================================
fprintf('--- Section 1: Configuration ---\n');

scs     = 15;
nRB     = 52;
snrDeg  = phase4.snrDegradation;

% SNR sweep — fine resolution
snrRange = -2:0.5:16;
nSNR     = length(snrRange);

% MORE SLOTS for smoother curves (BLER floor ~1/300 = 0.003)
nSlots   = 300;

% Dual environment configuration
envNames     = {'Suburban (NTN-TDL-C)', 'Rural (NTN-TDL-D)'};
envProfiles  = {'NTN-TDL-C', 'NTN-TDL-D'};
envDelays    = [params.channel.delaySpread.suburban, params.channel.delaySpread.rural];
nEnv         = length(envNames);

mobileDoppler = phase2.mobileDoppler;

% MCS configurations
mcsConfigs = {
    'QPSK',   120/1024,  'MCS 0 (QPSK R=0.12)';
    'QPSK',   449/1024,  'MCS 4 (QPSK R=0.44)';
    '16QAM',  340/1024,  'MCS 10 (16QAM R=0.33)';
    '16QAM',  490/1024,  'MCS 15 (16QAM R=0.48)';
    '64QAM',  567/1024,  'MCS 21 (64QAM R=0.55)';
};
nMCS = size(mcsConfigs, 1);

fprintf('  SCS: %d kHz | RBs: %d | SNR: %.1f to %.1f dB\n', scs, nRB, snrRange(1), snrRange(end));
fprintf('  Slots per SNR point: %d (smoother curves)\n', nSlots);
fprintf('  Transparent penalty: %.1f dB\n', snrDeg);
fprintf('  Environments: %s + %s\n', envNames{1}, envNames{2});
fprintf('  MCS configurations: %d\n\n', nMCS);
fprintf('  ESTIMATED RUNTIME: 20-40 minutes. Please be patient.\n\n');

%% =====================================================================
%  HELPER FUNCTION: Run BLER simulation for one environment
%  =====================================================================
function [bler_r, bler_t, ber_r, ber_t] = runBLER(carrier, pdsch, tbs, ...
    sr, chProfile, chDelay, mobDopp, snrVec, snrDeg, nSlots, params)
    
    nSNR = length(snrVec);
    bler_r = zeros(nSNR, 1);
    bler_t = zeros(nSNR, 1);
    ber_r  = zeros(nSNR, 1);
    ber_t  = zeros(nSNR, 1);
    
    % Channel
    tdl = nrTDLChannel;
    tdl.DelayProfile = chProfile;
    tdl.DelaySpread = chDelay;
    tdl.MaximumDopplerShift = mobDopp;
    tdl.SampleRate = sr;
    tdl.NumTransmitAntennas = 1;
    tdl.NumReceiveAntennas = 1;
    tdl.RandomStream = params.channel.randomStream;
    tdl.Seed = params.channel.seed;
    
    chInfo = info(tdl);
    maxDel = chInfo.MaximumChannelDelay;
    
    targetRate = 490/1024;
    
    for snrIdx = 1:nSNR
        snr_dB = snrVec(snrIdx);
        snr_t_dB = snr_dB - snrDeg;
        
        failR = 0; failT = 0;
        errR = 0; errT = 0; totBits = 0;
        
        for slot = 0:(nSlots-1)
            carrier.NSlot = slot;
            
            trBlk = randi([0 1], tbs, 1);
            enc = nrDLSCH;
            enc.TargetCodeRate = targetRate;
            setTransportBlock(enc, trBlk);
            
            [pIdx, pInfo] = nrPDSCHIndices(carrier, pdsch);
            coded = enc(pdsch.Modulation, pdsch.NumLayers, pInfo.G, 0);
            
            syms = nrPDSCH(carrier, pdsch, coded);
            dIdx = nrPDSCHDMRSIndices(carrier, pdsch);
            dSym = nrPDSCHDMRS(carrier, pdsch);
            
            g = nrResourceGrid(carrier);
            g(pIdx) = syms;
            g(dIdx) = dSym;
            
            tx = nrOFDMModulate(carrier, g);
            tx = [tx; zeros(maxDel, 1)];
            
            rx = tdl(tx);
            
            rxR = awgn(rx, snr_dB, 'measured');
            rxT = awgn(rx, snr_t_dB, 'measured');
            
            gR = nrOFDMDemodulate(carrier, rxR(1:end-maxDel));
            gT = nrOFDMDemodulate(carrier, rxT(1:end-maxDel));
            
            [eR, nR] = nrChannelEstimate(carrier, gR, dIdx, dSym);
            [eT, nT] = nrChannelEstimate(carrier, gT, dIdx, dSym);
            
            [qR, ~] = nrEqualizeMMSE(gR(pIdx), eR(pIdx), nR);
            [qT, ~] = nrEqualizeMMSE(gT(pIdx), eT(pIdx), nT);
            
            sR = nrPDSCHDecode(carrier, pdsch, qR, nR);
            sT = nrPDSCHDecode(carrier, pdsch, qT, nT);
            
            decR = nrDLSCHDecoder;
            decR.TargetCodeRate = targetRate;
            decR.TransportBlockLength = tbs;
            [rxBlkR, crcR] = decR(sR{1}, pdsch.Modulation, pdsch.NumLayers, 0);
            if crcR ~= 0, failR = failR + 1; end
            errR = errR + sum(rxBlkR ~= trBlk);
            
            decT = nrDLSCHDecoder;
            decT.TargetCodeRate = targetRate;
            decT.TransportBlockLength = tbs;
            [rxBlkT, crcT] = decT(sT{1}, pdsch.Modulation, pdsch.NumLayers, 0);
            if crcT ~= 0, failT = failT + 1; end
            errT = errT + sum(rxBlkT ~= trBlk);
            
            totBits = totBits + tbs;
        end
        
        bler_r(snrIdx) = failR / nSlots;
        bler_t(snrIdx) = failT / nSlots;
        ber_r(snrIdx)  = errR / totBits;
        ber_t(snrIdx)  = errT / totBits;
    end
end

%% =====================================================================
%  SECTION 2: BLER vs SNR — BOTH PAYLOADS, BOTH ENVIRONMENTS
%  =====================================================================
fprintf('--- Section 2: BLER vs SNR — Dual Environment ---\n');

modScheme      = '16QAM';
targetCodeRate = 490/1024;

carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = scs;
carrier.NSizeGrid = nRB;
carrier.CyclicPrefix = 'Normal';

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

carrier.NSlot = 0;
[~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, ...
    length(pdsch.PRBSet), pdschInfo.NREPerPRB, targetCodeRate);

[~, ofdmInfo] = nrOFDMModulate(carrier, nrResourceGrid(carrier));
sr = ofdmInfo.SampleRate;

fprintf('  TBS = %d bits | SR = %.2f MHz\n', tbs, sr/1e6);

% Store results per environment
bler_regen  = zeros(nSNR, nEnv);
bler_transp = zeros(nSNR, nEnv);
ber_coded_regen  = zeros(nSNR, nEnv);
ber_coded_transp = zeros(nSNR, nEnv);

totalStart = tic;

for envIdx = 1:nEnv
    fprintf('\n  === Environment: %s ===\n', envNames{envIdx});
    fprintf('    Profile: %s | Delay Spread: %.0f ns | Slots: %d\n', ...
        envProfiles{envIdx}, envDelays(envIdx)*1e9, nSlots);
    
    [blR, blT, beR, beT] = runBLER(carrier, pdsch, tbs, sr, ...
        envProfiles{envIdx}, envDelays(envIdx), mobileDoppler, ...
        snrRange, snrDeg, nSlots, params);
    
    bler_regen(:, envIdx)  = blR;
    bler_transp(:, envIdx) = blT;
    ber_coded_regen(:, envIdx)  = beR;
    ber_coded_transp(:, envIdx) = beT;
    
    % Print key points
    for snrIdx = 1:nSNR
        if bler_regen(snrIdx, envIdx) > 0 || bler_transp(snrIdx, envIdx) > 0 || snrRange(snrIdx) <= 0
            fprintf('    SNR=%5.1f | R: BLER=%.3f | T: BLER=%.3f\n', ...
                snrRange(snrIdx), bler_regen(snrIdx, envIdx), bler_transp(snrIdx, envIdx));
        end
    end
end

elapsed_sec2 = toc(totalStart);
fprintf('\n  Section 2 complete in %.1f seconds (%.1f minutes).\n\n', elapsed_sec2, elapsed_sec2/60);

%% =====================================================================
%  SECTION 3: BLER vs SNR — MULTIPLE MCS (Suburban only)
%  =====================================================================
fprintf('--- Section 3: BLER vs SNR — Multiple MCS (Suburban) ---\n');

snrMCS = -6:1:24;
nSNR_MCS = length(snrMCS);
nSlotsMCS = 80;

bler_mcs_regen = zeros(nSNR_MCS, nMCS);

% Channel for MCS sweep (Suburban)
tdlMCS = nrTDLChannel;
tdlMCS.DelayProfile = 'NTN-TDL-C';
tdlMCS.DelaySpread = params.channel.delaySpread.suburban;
tdlMCS.MaximumDopplerShift = mobileDoppler;
tdlMCS.SampleRate = sr;
tdlMCS.NumTransmitAntennas = 1;
tdlMCS.NumReceiveAntennas = 1;
tdlMCS.RandomStream = params.channel.randomStream;
tdlMCS.Seed = params.channel.seed;
chInfoMCS = info(tdlMCS);
maxChDelayMCS = chInfoMCS.MaximumChannelDelay;

for mIdx = 1:nMCS
    modMCS  = mcsConfigs{mIdx, 1};
    rateMCS = mcsConfigs{mIdx, 2};
    lblMCS  = mcsConfigs{mIdx, 3};
    
    fprintf('  %s\n', lblMCS);
    
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
            tx = [tx; zeros(maxChDelayMCS, 1)];
            
            rx = tdlMCS(tx);
            rx = awgn(rx, snr_dB, 'measured');
            
            rxG = nrOFDMDemodulate(carrier, rx(1:end-maxChDelayMCS));
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
    
    idx10 = find(bler_mcs_regen(:, mIdx) <= 0.1, 1, 'first');
    if ~isempty(idx10)
        fprintf('    10%% BLER at SNR ~%.1f dB\n', snrMCS(idx10));
    end
end
fprintf('\n');

%% =====================================================================
%  SECTION 4: UNCODED BER REFERENCE
%  =====================================================================
fprintf('--- Section 4: Uncoded BER reference ---\n');

M = 16;
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
fprintf('  Done.\n\n');

%% =====================================================================
%  SECTION 5: PLOTS
%  =====================================================================
fprintf('--- Section 5: Generating plots ---\n');

colors = lines(8);

% ---- Figure 1: BLER vs SNR — Both Payloads, SUBURBAN ----
figure('Name', 'BLER Suburban', 'Position', [100 100 900 550]);
semilogy(snrRange, bler_regen(:,1), '-bs', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'Regenerative');
hold on;
semilogy(snrRange, bler_transp(:,1), '-ro', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', sprintf('Transparent (%.1f dB penalty)', snrDeg));
yline(0.1, '--k', '10% BLER Target', 'LineWidth', 1.5, 'FontSize', 10, ...
    'LabelHorizontalAlignment', 'left');
hold off;
xlabel('SNR (dB)', 'FontSize', 12);
ylabel('Block Error Rate (BLER)', 'FontSize', 12);
title('BLER vs SNR — Suburban (NTN-TDL-C), 16QAM R=0.48', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 10);
grid on; set(gca, 'FontSize', 11);
ylim([1e-3 1]);
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_suburban.png'));
fprintf('  Saved: phase7_bler_suburban.png\n');

% ---- Figure 2: BLER vs SNR — Both Payloads, RURAL ----
figure('Name', 'BLER Rural', 'Position', [100 100 900 550]);
semilogy(snrRange, bler_regen(:,2), '-bs', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'Regenerative');
hold on;
semilogy(snrRange, bler_transp(:,2), '-ro', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', sprintf('Transparent (%.1f dB penalty)', snrDeg));
yline(0.1, '--k', '10% BLER Target', 'LineWidth', 1.5, 'FontSize', 10, ...
    'LabelHorizontalAlignment', 'left');
hold off;
xlabel('SNR (dB)', 'FontSize', 12);
ylabel('Block Error Rate (BLER)', 'FontSize', 12);
title('BLER vs SNR — Rural (NTN-TDL-D), 16QAM R=0.48', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 10);
grid on; set(gca, 'FontSize', 11);
ylim([1e-3 1]);
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_rural.png'));
fprintf('  Saved: phase7_bler_rural.png\n');

% ---- Figure 3: ENVIRONMENT COMPARISON — Regenerative only ----
figure('Name', 'Env Comparison', 'Position', [100 100 900 550]);
semilogy(snrRange, bler_regen(:,1), '-bo', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Suburban (NTN-TDL-C)');
hold on;
semilogy(snrRange, bler_regen(:,2), '-gs', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Rural (NTN-TDL-D)');
semilogy(snrRange, bler_transp(:,1), '--r^', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Suburban — Transparent');
semilogy(snrRange, bler_transp(:,2), '--md', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Rural — Transparent');
yline(0.1, '--k', '10% BLER', 'LineWidth', 1.5, 'FontSize', 9);
hold off;
xlabel('SNR (dB)', 'FontSize', 12);
ylabel('BLER', 'FontSize', 12);
title('Environment Comparison — Suburban vs Rural, Both Payloads', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 9);
grid on; set(gca, 'FontSize', 11);
ylim([1e-3 1]);
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_env_comparison.png'));
fprintf('  Saved: phase7_bler_env_comparison.png\n');

% ---- Figure 4: Multi-MCS BLER (Regenerative, Suburban) ----
figure('Name', 'Multi-MCS', 'Position', [100 100 900 550]);
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

% ---- Figure 5: Coded vs Uncoded BER ----
figure('Name', 'BER Comparison', 'Position', [100 100 900 550]);
semilogy(snrRange, ber_uncoded, '-k^', 'LineWidth', 1.5, 'MarkerSize', 5, ...
    'DisplayName', 'Uncoded 16QAM (AWGN)');
hold on;
semilogy(snrRange, ber_coded_regen(:,1), '-bs', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'LDPC Coded — Regen (Suburban)');
semilogy(snrRange, ber_coded_transp(:,1), '-ro', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'LDPC Coded — Transp (Suburban)');
semilogy(snrRange, ber_coded_regen(:,2), '--gs', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'LDPC Coded — Regen (Rural)');
hold off;
xlabel('SNR (dB)', 'FontSize', 12);
ylabel('Bit Error Rate (BER)', 'FontSize', 12);
title('Coded vs Uncoded BER — LDPC Coding Gain', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 9);
grid on; set(gca, 'FontSize', 11);
ylim([1e-6 1]);
saveas(gcf, fullfile(params.outputDir, 'phase7_ber_coded_vs_uncoded.png'));
fprintf('  Saved: phase7_ber_coded_vs_uncoded.png\n');

% ---- Figure 6: HARQ Impact ----
figure('Name', 'HARQ', 'Position', [100 100 1000 550]);

subplot(1, 2, 1);
semilogy(snrRange, bler_regen(:,1), '-bs', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Regen 1st Tx');
hold on;
bler_harq1 = bler_regen(:,1) .* bler_regen(:,1);
bler_harq2 = bler_harq1 .* bler_regen(:,1);
semilogy(snrRange, bler_harq1, '-g^', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Regen + 1 retx');
semilogy(snrRange, bler_harq2, '-md', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Regen + 2 retx');
yline(0.1, '--k', '10% BLER', 'LineWidth', 1);
yline(0.01, ':k', '1% BLER', 'LineWidth', 1);
hold off;
xlabel('SNR (dB)', 'FontSize', 11);
ylabel('BLER', 'FontSize', 11);
title('Regenerative — HARQ Combining', 'FontSize', 12);
legend('Location', 'southwest', 'FontSize', 8);
grid on; set(gca, 'FontSize', 10);
ylim([1e-6 1]);

subplot(1, 2, 2);
semilogy(snrRange, bler_transp(:,1), '-ro', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Transparent 1st Tx');
hold on;
yline(0.1, '--k', '10% BLER', 'LineWidth', 1);
yline(0.01, ':k', '1% BLER', 'LineWidth', 1);
text(mean(snrRange), 0.4, 'HARQ DISABLED', 'FontSize', 14, ...
    'HorizontalAlignment', 'center', 'Color', [0.7 0 0], 'FontWeight', 'bold');
text(mean(snrRange), 0.18, '(RTT exceeds timer)', 'FontSize', 10, ...
    'HorizontalAlignment', 'center', 'Color', [0.5 0 0]);
hold off;
xlabel('SNR (dB)', 'FontSize', 11);
ylabel('BLER', 'FontSize', 11);
title('Transparent — No HARQ', 'FontSize', 12);
legend('Location', 'southwest', 'FontSize', 9);
grid on; set(gca, 'FontSize', 10);
ylim([1e-6 1]);

sgtitle('HARQ Impact — Regenerative vs Transparent (Suburban)', ...
    'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_harq.png'));
fprintf('  Saved: phase7_bler_harq.png\n');

%% =====================================================================
%  SECTION 6: VALIDATION CHECKS
%  =====================================================================
fprintf('\n--- Section 6: Validation checks ---\n');

for envIdx = 1:nEnv
    fprintf('\n  === %s ===\n', envNames{envIdx});
    
    idx10_R = find(bler_regen(:, envIdx) <= 0.1, 1, 'first');
    idx10_T = find(bler_transp(:, envIdx) <= 0.1, 1, 'first');
    
    if ~isempty(idx10_R) && ~isempty(idx10_T)
        snr10_R = snrRange(idx10_R);
        snr10_T = snrRange(idx10_T);
        shift = snr10_T - snr10_R;
        fprintf('  10%% BLER: Regen=%.1f dB | Transp=%.1f dB | Shift=%.1f dB\n', ...
            snr10_R, snr10_T, shift);
    else
        fprintf('  WARNING: 10%% BLER crossing not found.\n');
    end
    
    fprintf('  [CHECK] Regen BLER <= Transparent... ');
    if all(bler_regen(:,envIdx) <= bler_transp(:,envIdx) + 0.01)
        fprintf('PASS\n');
    else
        fprintf('WARNING\n');
    end
    
    fprintf('  [CHECK] BLER=0 at high SNR (regen)... ');
    if bler_regen(end, envIdx) < 0.01, fprintf('PASS\n'); else, fprintf('WARNING\n'); end
    
    fprintf('  [CHECK] BLER~1 at low SNR... ');
    if bler_regen(1, envIdx) > 0.8, fprintf('PASS\n'); else, fprintf('WARNING\n'); end
end

fprintf('\n');

%% =====================================================================
%  SECTION 7: EXPORT
%  =====================================================================
fprintf('--- Section 7: Exporting results ---\n');

phase7 = struct();

phase7.snrRange        = snrRange;
phase7.envNames        = envNames;
phase7.envProfiles     = envProfiles;
phase7.bler_regen      = bler_regen;       % [nSNR x nEnv]
phase7.bler_transp     = bler_transp;      % [nSNR x nEnv]
phase7.ber_coded_regen  = ber_coded_regen;
phase7.ber_coded_transp = ber_coded_transp;
phase7.ber_uncoded     = ber_uncoded;

phase7.snrMCS          = snrMCS;
phase7.bler_mcs_regen  = bler_mcs_regen;
phase7.mcsConfigs      = mcsConfigs;

phase7.bler_harq1      = bler_harq1;
phase7.bler_harq2      = bler_harq2;

phase7.snrDegradation  = snrDeg;
phase7.nSlots          = nSlots;

outFile = fullfile(params.outputDir, 'phase7_results.mat');
save(outFile, 'phase7', '-v7.3');
fprintf('  Saved: %s\n', outFile);

%% =====================================================================
%  SUMMARY
%  =====================================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 7 COMPLETE (v2 — Dual Environment)\n');
fprintf('============================================================\n');
for envIdx = 1:nEnv
    idx10_R = find(bler_regen(:,envIdx) <= 0.1, 1, 'first');
    idx10_T = find(bler_transp(:,envIdx) <= 0.1, 1, 'first');
    if ~isempty(idx10_R) && ~isempty(idx10_T)
        fprintf('  %s:\n', envNames{envIdx});
        fprintf('    10%% BLER: Regen=%.1f dB | Transp=%.1f dB | Shift=%.1f dB\n', ...
            snrRange(idx10_R), snrRange(idx10_T), snrRange(idx10_T)-snrRange(idx10_R));
    end
end
fprintf('  Slots per point: %d (smooth curves)\n', nSlots);
fprintf('  Multi-MCS: %d configurations\n', nMCS);
fprintf('  HARQ: Enabled for regen, disabled for transparent\n');
fprintf('  Figures: 6\n');
fprintf('\n  ============= PROJECT COMPLETE =============\n');
fprintf('============================================================\n');
