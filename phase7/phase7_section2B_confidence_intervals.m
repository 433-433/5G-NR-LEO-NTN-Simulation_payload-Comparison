%% ========================================================================
%  PHASE 7 — SECTION 2B: BLER with 95% CONFIDENCE INTERVALS (STANDALONE)
%  ========================================================================
%  Addresses Reviewer Theme E ("no confidence intervals").
%
%  FULLY SELF-CONTAINED — run it on its own. Rebuilds carrier/pdsch/
%  channel objects, then repeats the REAL Section 2 LDPC/CRC BLER
%  simulation over N_SEED independent channel+noise realizations and
%  reports mean BLER with a 95% CI at each SNR.
%
%  Requires: config/systemParams.m, helpers/, and saved
%            phase2_results.mat + phase4_results.mat.
%
%  Start with N_SEED=15, nSlotsCI=60. Lower if too slow.
% ========================================================================
clc; clear; close all;

fprintf('--- Section 2B: BLER with 95%% Confidence Intervals (standalone) ---\n');

%% --- Setup (rebuilds everything Section 1-2 would define) ---
addpath('config'); addpath('helpers');
params = systemParams();

% ---- Safety fallbacks (in case systemParams lacks these fields) ----
if ~isfield(params,'outputDir') || isempty(params.outputDir)
    params.outputDir = pwd;
end
if ~exist(params.outputDir,'dir'); mkdir(params.outputDir); end
if ~isfield(params,'channel');            params.channel = struct;            end
if ~isfield(params.channel,'randomStream');params.channel.randomStream='mt19937ar with seed'; end
if ~isfield(params.channel,'seed');        params.channel.seed = 42;           end

% ---- Prerequisite values taken directly from the paper (no .mat needed) ----
% The phase2/phase4 .mat files are not required: the only quantities this
% script needs from them are fixed and known from the published results.
snrDeg         = 3.4;      % transparent aggregate SNR penalty [dB] (Phase 4)
delaySpread    = 50e-9;    % suburban NTN-TDL-C delay spread [s] (50 ns)
mobileDoppler  = 5.6;      % UE mobility Doppler [Hz] (3 km/h pedestrian)

scs = 15; nRB = 52;
snrRange = unique([-2:1:3, 3.5:0.25:6, 6:1:7.5, 7.5:0.25:9.5, 10:1:16]); nSNR = length(snrRange);
channelProfile = 'NTN-TDL-C';
targetCodeRate = 490/1024;

carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = scs; carrier.NSizeGrid = nRB;
carrier.CyclicPrefix = 'Normal';

pdsch = nrPDSCHConfig;
pdsch.Modulation = '16QAM'; pdsch.NumLayers = 1;
pdsch.PRBSet = (0:nRB-1)'; pdsch.SymbolAllocation = [0 14];
pdsch.MappingType = 'A';
pdsch.DMRS.DMRSConfigurationType = 1; pdsch.DMRS.DMRSLength = 1;
pdsch.DMRS.DMRSAdditionalPosition = 1; pdsch.DMRS.DMRSTypeAPosition = 2;

carrier.NSlot = 0;
[~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, ...
    length(pdsch.PRBSet), pdschInfo.NREPerPRB, targetCodeRate);

[~, ofdmInfo] = nrOFDMModulate(carrier, nrResourceGrid(carrier));
sr = ofdmInfo.SampleRate;

tdlChan = nrTDLChannel;
tdlChan.DelayProfile = channelProfile;
tdlChan.DelaySpread = delaySpread;
tdlChan.MaximumDopplerShift = mobileDoppler;
tdlChan.SampleRate = sr;
tdlChan.NumTransmitAntennas = 1; tdlChan.NumReceiveAntennas = 1;
tdlChan.RandomStream = params.channel.randomStream;
tdlChan.Seed = params.channel.seed;
maxChDelay = info(tdlChan).MaximumChannelDelay;

fprintf('  Setup done: TBS=%d bits, nSNR=%d, penalty=%.1f dB\n\n', tbs, nSNR, snrDeg);

%% --- Confidence-interval sweep ---
N_SEED   = 8;    % 8 seeds is sufficient for a stable 95% CI
nSlotsCI = 40;   % 40 slots/point keeps runtime manageable
z95      = 1.96;

blerR_all = zeros(N_SEED, nSNR);
blerT_all = zeros(N_SEED, nSNR);

ciStart = tic;
for seed = 1:N_SEED
    release(tdlChan);            % allow non-tunable Seed to be changed
    tdlChan.Seed = 1000 + seed;
    reset(tdlChan);

    for snrIdx = 1:nSNR
        snr_dB        = snrRange(snrIdx);
        snr_transp_dB = snr_dB - snrDeg;
        tbFailR = 0; tbFailT = 0;

        for slot = 0:(nSlotsCI-1)
            carrier.NSlot = slot;

            trBlk = randi([0 1], tbs, 1);
            enc = nrDLSCH; enc.TargetCodeRate = targetCodeRate;
            setTransportBlock(enc, trBlk);

            [pdschIndices, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
            codedBits = enc(pdsch.Modulation, pdsch.NumLayers, pdschInfo.G, 0);

            pdschSymbols = nrPDSCH(carrier, pdsch, codedBits);
            dmrsIndices  = nrPDSCHDMRSIndices(carrier, pdsch);
            dmrsSymbols  = nrPDSCHDMRS(carrier, pdsch);

            grid = nrResourceGrid(carrier);
            grid(pdschIndices) = pdschSymbols;
            grid(dmrsIndices)  = dmrsSymbols;

            txWaveform = nrOFDMModulate(carrier, grid);
            txWaveform = [txWaveform; zeros(maxChDelay, 1)];
            rxWaveform = tdlChan(txWaveform);

            rxR = awgn(rxWaveform, snr_dB,        'measured');
            rxT = awgn(rxWaveform, snr_transp_dB, 'measured');

            rxGridR = nrOFDMDemodulate(carrier, rxR(1:end-maxChDelay));
            rxGridT = nrOFDMDemodulate(carrier, rxT(1:end-maxChDelay));

            [estChR, noiseR] = nrChannelEstimate(carrier, rxGridR, dmrsIndices, dmrsSymbols);
            [estChT, noiseT] = nrChannelEstimate(carrier, rxGridT, dmrsIndices, dmrsSymbols);

            eqR = nrEqualizeMMSE(rxGridR(pdschIndices), estChR(pdschIndices), noiseR);
            eqT = nrEqualizeMMSE(rxGridT(pdschIndices), estChT(pdschIndices), noiseT);

            softR = nrPDSCHDecode(carrier, pdsch, eqR, noiseR);
            softT = nrPDSCHDecode(carrier, pdsch, eqT, noiseT);

            decR = nrDLSCHDecoder; decR.TargetCodeRate = targetCodeRate;
            decR.TransportBlockLength = tbs;
            [~, crcR] = decR(softR{1}, pdsch.Modulation, pdsch.NumLayers, 0);
            if crcR ~= 0, tbFailR = tbFailR + 1; end

            decT = nrDLSCHDecoder; decT.TargetCodeRate = targetCodeRate;
            decT.TransportBlockLength = tbs;
            [~, crcT] = decT(softT{1}, pdsch.Modulation, pdsch.NumLayers, 0);
            if crcT ~= 0, tbFailT = tbFailT + 1; end
        end

        blerR_all(seed, snrIdx) = tbFailR / nSlotsCI;
        blerT_all(seed, snrIdx) = tbFailT / nSlotsCI;
    end
    fprintf('    seed %2d/%d done (%.0f s elapsed)\n', seed, N_SEED, toc(ciStart));
end

%% --- Mean and 95% CI ---
mR  = mean(blerR_all, 1);  ciR = z95 * std(blerR_all, 0, 1) / sqrt(N_SEED);
mT  = mean(blerT_all, 1);  ciT = z95 * std(blerT_all, 0, 1) / sqrt(N_SEED);

fprintf('\n  SNR   Regen mean (95%%CI)       Transp mean (95%%CI)\n');
for i = 1:nSNR
    fprintf('  %5.1f  %.4f (+/-%.4f)      %.4f (+/-%.4f)\n', ...
        snrRange(i), mR(i), ciR(i), mT(i), ciT(i));
end

iR = find(mR <= 0.1, 1, 'first'); iT = find(mT <= 0.1, 1, 'first');
if ~isempty(iR) && ~isempty(iT)
    fprintf('\n  10%% BLER (mean): Regen %.1f dB | Transp %.1f dB | Shift %.1f dB\n', ...
        snrRange(iR), snrRange(iT), snrRange(iT)-snrRange(iR));
end

save(fullfile(params.outputDir,'phase7_bler_ci.mat'), ...
    'snrRange','mR','ciR','mT','ciT','N_SEED','nSlotsCI');

%% --- Figure with error bars ---
figure('Name','BLER 95% CI','Position',[100 100 900 550]);
errorbar(snrRange, mR, ciR, '-bs', 'LineWidth',1.8,'MarkerSize',5, ...
    'DisplayName','Regenerative (mean \pm 95% CI)'); hold on;
errorbar(snrRange, mT, ciT, '-ro', 'LineWidth',1.8,'MarkerSize',5, ...
    'DisplayName','Transparent (mean \pm 95% CI)');
set(gca,'YScale','log');
yl = yline(0.1,'--k','10% BLER Target','LineWidth',1.5); yl.HandleVisibility='off';
hold off; grid on;
xlabel('SNR (dB)','FontSize',12); ylabel('BLER','FontSize',12);
title(sprintf('Suburban BLER with 95%% CI (%d seeds, %d slots)',N_SEED,nSlotsCI),'FontSize',13);
legend('Location','southwest','FontSize',10); ylim([1e-3 1]);
saveas(gcf, fullfile(params.outputDir,'phase7_bler_suburban_ci.png'));
fprintf('  Saved: phase7_bler_suburban_ci.png\n');