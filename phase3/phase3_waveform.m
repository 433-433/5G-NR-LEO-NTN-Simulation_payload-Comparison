%% ========================================================================
%  PHASE 3: 5G NR Waveform Generation
%  ========================================================================
%  Performance Analysis of 5G NR in LEO Non-Terrestrial Networks
%
%  Generates NR-compliant waveforms using 5G Toolbox high-level functions.
%  Replaces manual IFFT-based waveform generation with:
%    - nrCarrierConfig / nrPDSCHConfig / nrPUSCHConfig
%    - nrOFDMModulate / nrOFDMDemodulate
%    - Proper resource grid, DMRS placement, CP handling
%
%  Waveforms generated for all 4 data-channel SCS values:
%    15 kHz, 30 kHz, 60 kHz, 120 kHz
%  Both CP-OFDM (downlink) and DFT-s-OFDM (uplink) waveforms.
%
%  3GPP References:
%    TS 38.211         — Physical channels and modulation
%    TS 38.101-1 T5.3.2-1 — RB allocation per SCS/bandwidth
%    TS 38.214         — MCS tables, transport block sizing
%  ========================================================================
clc; clear; close all;

%% Add paths and load previous results
addpath('config');
addpath('helpers');
params = systemParams();

fprintf('============================================================\n');
fprintf('  PHASE 3: 5G NR Waveform Generation\n');
fprintf('  LEO NTN — 5G NR Performance Analysis\n');
fprintf('============================================================\n\n');

% Load Phase 2 results
fprintf('--- Loading Phase 2 results ---\n');
p2File = fullfile(params.outputDir, 'phase2_results.mat');
if ~exist(p2File, 'file')
    error('Phase 2 results not found. Run phase2_channel.m first.');
end
load(p2File, 'phase2');
fprintf('  Loaded: %s\n\n', p2File);

%% =====================================================================
%  SECTION 1: SCS AND RESOURCE BLOCK CONFIGURATION
%  =====================================================================
fprintf('--- Section 1: SCS and Resource Block Configuration ---\n');

% Data-channel SCS values (240 kHz is SSB-only, excluded from data)
scsValues   = [15, 30, 60, 120];   % kHz
nSCS        = length(scsValues);
bwMHz       = 10;                   % Channel bandwidth [MHz]

% RB count per SCS for 10 MHz (TS 38.101-1 Table 5.3.2-1)
% 120 kHz doesn't support 10 MHz; use 20 MHz for it
rbCounts    = [52, 24, 11, 11];    % RBs for [15, 30, 60, 120] kHz
bwUsed_MHz  = [10, 10, 10, 20];   % Actual BW used per SCS

fprintf('  Channel bandwidth: %d MHz (20 MHz for 120 kHz SCS)\n', bwMHz);
fprintf('  %-10s | %-6s | %-10s | %-12s | %-12s\n', ...
    'SCS (kHz)', 'mu', 'RBs', 'BW Used', 'Slot Duration');
fprintf('  %s\n', repmat('-', 1, 65));

for k = 1:nSCS
    slotDur_ms = 1 / (2^(log2(scsValues(k)/15)));  % Slot duration in ms
    fprintf('  %-10d | %-6d | %-10d | %-10d MHz | %.4f ms\n', ...
        scsValues(k), log2(scsValues(k)/15), rbCounts(k), bwUsed_MHz(k), slotDur_ms);
end
fprintf('\n');

%% =====================================================================
%  SECTION 2: DOWNLINK WAVEFORM GENERATION (CP-OFDM via PDSCH)
%  =====================================================================
fprintf('--- Section 2: Generating Downlink CP-OFDM Waveforms ---\n');

% Store waveform data per SCS
dlWaveforms  = cell(1, nSCS);
dlGrids      = cell(1, nSCS);
dlCarriers   = cell(1, nSCS);
dlPdschCfgs  = cell(1, nSCS);
dlOfdmInfo   = cell(1, nSCS);
dlTBS        = zeros(1, nSCS);    % Transport block size per SCS

numSlots = 10;  % Generate 10 slots of data per SCS

for k = 1:nSCS
    fprintf('  [SCS=%d kHz] ', scsValues(k));
    
    % --- Carrier Configuration ---
    carrier = nrCarrierConfig;
    carrier.SubcarrierSpacing = scsValues(k);
    carrier.NSizeGrid         = rbCounts(k);
    carrier.CyclicPrefix      = 'Normal';
    
    % --- PDSCH Configuration ---
    pdsch = nrPDSCHConfig;
    pdsch.Modulation        = '16QAM';
    pdsch.NumLayers         = 1;
    pdsch.PRBSet            = (0:rbCounts(k)-1)';   % Full bandwidth allocation
    pdsch.SymbolAllocation  = [0 14];                % Full slot (14 symbols)
    pdsch.MappingType       = 'A';
    
    % DMRS configuration
    pdsch.DMRS.DMRSConfigurationType = 1;
    pdsch.DMRS.DMRSLength            = 1;
    pdsch.DMRS.DMRSAdditionalPosition = 1;
    pdsch.DMRS.DMRSTypeAPosition     = 2;
    
    % --- Generate waveform over multiple slots ---
    fullWaveform = [];
    fullGrid     = [];
    
    for slot = 0:(numSlots-1)
        carrier.NSlot = slot;
        
        % Get PDSCH indices and info
        [pdschIndices, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
        
        % Generate random data bits and modulate
        numBits = pdschInfo.G;
        dataBits = randi([0 1], numBits, 1);
        pdschSymbols = nrPDSCH(carrier, pdsch, dataBits);
        
        % Create resource grid and map PDSCH
        grid = nrResourceGrid(carrier);
        grid(pdschIndices) = pdschSymbols;
        
        % Generate DMRS and map
        dmrsIndices = nrPDSCHDMRSIndices(carrier, pdsch);
        dmrsSymbols = nrPDSCHDMRS(carrier, pdsch);
        grid(dmrsIndices) = dmrsSymbols;
        
        % OFDM modulate
        [waveform, ofdmInfo] = nrOFDMModulate(carrier, grid);
        
        fullWaveform = [fullWaveform; waveform];
        fullGrid     = cat(2, fullGrid, grid);
        
        % Compute TBS for first slot only
        if slot == 0
            % Target code rate ~0.5 (MCS ~15 range)
            targetCodeRate = 0.5;
            nRE = pdschInfo.NREPerPRB * length(pdsch.PRBSet);
            tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, ...
                length(pdsch.PRBSet), pdschInfo.NREPerPRB, targetCodeRate);
            dlTBS(k) = tbs;
        end
    end
    
    % Store
    dlWaveforms{k}  = fullWaveform;
    dlGrids{k}      = fullGrid;
    dlCarriers{k}   = carrier;
    dlPdschCfgs{k}  = pdsch;
    dlOfdmInfo{k}   = ofdmInfo;
    
    fprintf('Waveform: %d samples | SR: %.2f MHz | Grid: [%d x %d] | TBS: %d bits\n', ...
        length(fullWaveform), ofdmInfo.SampleRate/1e6, ...
        size(fullGrid, 1), size(fullGrid, 2), dlTBS(k));
end
fprintf('\n');

%% =====================================================================
%  SECTION 3: UPLINK WAVEFORM GENERATION (DFT-s-OFDM via PUSCH)
%  =====================================================================
fprintf('--- Section 3: Generating Uplink DFT-s-OFDM Waveforms ---\n');

ulWaveforms  = cell(1, nSCS);
ulGrids      = cell(1, nSCS);
ulCarriers   = cell(1, nSCS);
ulPuschCfgs  = cell(1, nSCS);
ulOfdmInfo   = cell(1, nSCS);
ulTBS        = zeros(1, nSCS);

for k = 1:nSCS
    fprintf('  [SCS=%d kHz] ', scsValues(k));
    
    % --- Carrier Configuration ---
    carrier = nrCarrierConfig;
    carrier.SubcarrierSpacing = scsValues(k);
    carrier.NSizeGrid         = rbCounts(k);
    carrier.CyclicPrefix      = 'Normal';
    
    % --- PUSCH Configuration ---
    pusch = nrPUSCHConfig;
    pusch.Modulation          = '16QAM';
    pusch.NumLayers           = 1;
    pusch.PRBSet              = (0:rbCounts(k)-1)';
    pusch.SymbolAllocation    = [0 14];
    pusch.MappingType         = 'A';
    pusch.TransformPrecoding  = true;    % DFT-s-OFDM (key for UL in NTN)
    
    % DMRS for PUSCH
    pusch.DMRS.DMRSConfigurationType = 1;
    pusch.DMRS.DMRSLength            = 1;
    pusch.DMRS.DMRSAdditionalPosition = 1;
    pusch.DMRS.DMRSTypeAPosition     = 2;
    
    % --- Generate waveform over multiple slots ---
    fullWaveform = [];
    fullGrid     = [];
    
    for slot = 0:(numSlots-1)
        carrier.NSlot = slot;
        
        [puschIndices, puschInfo] = nrPUSCHIndices(carrier, pusch);
        
        numBits = puschInfo.G;
        dataBits = randi([0 1], numBits, 1);
        puschSymbols = nrPUSCH(carrier, pusch, dataBits);
        
        grid = nrResourceGrid(carrier);
        grid(puschIndices) = puschSymbols;
        
        % DMRS
        dmrsIndices = nrPUSCHDMRSIndices(carrier, pusch);
        dmrsSymbols = nrPUSCHDMRS(carrier, pusch);
        grid(dmrsIndices) = dmrsSymbols;
        
        [waveform, ofdmInfo] = nrOFDMModulate(carrier, grid);
        
        fullWaveform = [fullWaveform; waveform];
        fullGrid     = cat(2, fullGrid, grid);
        
        if slot == 0
            targetCodeRate = 0.5;
            tbs = nrTBS(pusch.Modulation, pusch.NumLayers, ...
                length(pusch.PRBSet), puschInfo.NREPerPRB, targetCodeRate);
            ulTBS(k) = tbs;
        end
    end
    
    ulWaveforms{k}  = fullWaveform;
    ulGrids{k}      = fullGrid;
    ulCarriers{k}   = carrier;
    ulPuschCfgs{k}  = pusch;
    ulOfdmInfo{k}   = ofdmInfo;
    
    fprintf('Waveform: %d samples | SR: %.2f MHz | Grid: [%d x %d] | TBS: %d bits\n', ...
        length(fullWaveform), ofdmInfo.SampleRate/1e6, ...
        size(fullGrid, 1), size(fullGrid, 2), ulTBS(k));
end
fprintf('\n');

%% =====================================================================
%  SECTION 4: WAVEFORM SPECTRUM VISUALIZATION
%  =====================================================================
fprintf('--- Section 4: Spectrum visualization ---\n');

colors = lines(nSCS);

% --- DL Spectra ---
figure('Name', 'DL Spectra', 'Position', [100 100 1100 700]);
for k = 1:nSCS
    subplot(2, 2, k);
    sr = dlOfdmInfo{k}.SampleRate;
    nfft = 2048;
    [pxx, f] = pwelch(dlWaveforms{k}, hanning(nfft), nfft/2, nfft, sr, 'centered');
    plot(f/1e6, 10*log10(pxx/max(pxx)), 'Color', colors(k,:), 'LineWidth', 1.0);
    xlabel('Frequency (MHz)', 'FontSize', 10);
    ylabel('Norm. PSD (dB)', 'FontSize', 10);
    title(sprintf('CP-OFDM DL — SCS %d kHz (%d RBs)', scsValues(k), rbCounts(k)), 'FontSize', 11);
    grid on; set(gca, 'FontSize', 9); ylim([-60 5]);
end
sgtitle('Downlink CP-OFDM Waveform Spectra — All SCS', 'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase3_dl_spectra.png'));
fprintf('  Saved: phase3_dl_spectra.png\n');

% --- UL Spectra ---
figure('Name', 'UL Spectra', 'Position', [100 100 1100 700]);
for k = 1:nSCS
    subplot(2, 2, k);
    sr = ulOfdmInfo{k}.SampleRate;
    nfft = 2048;
    [pxx, f] = pwelch(ulWaveforms{k}, hanning(nfft), nfft/2, nfft, sr, 'centered');
    plot(f/1e6, 10*log10(pxx/max(pxx)), 'Color', colors(k,:), 'LineWidth', 1.0);
    xlabel('Frequency (MHz)', 'FontSize', 10);
    ylabel('Norm. PSD (dB)', 'FontSize', 10);
    title(sprintf('DFT-s-OFDM UL — SCS %d kHz (%d RBs)', scsValues(k), rbCounts(k)), 'FontSize', 11);
    grid on; set(gca, 'FontSize', 9); ylim([-60 5]);
end
sgtitle('Uplink DFT-s-OFDM Waveform Spectra — All SCS', 'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase3_ul_spectra.png'));
fprintf('  Saved: phase3_ul_spectra.png\n');

%% =====================================================================
%  SECTION 5: RESOURCE GRID VISUALIZATION
%  =====================================================================
fprintf('--- Section 5: Resource grid visualization ---\n');

figure('Name', 'Resource Grids', 'Position', [100 100 1100 700]);
for k = 1:nSCS
    subplot(2, 2, k);
    % Show first 2 slots of DL grid
    nSymPerSlot = 14;
    showSyms = min(2 * nSymPerSlot, size(dlGrids{k}, 2));
    gridSlice = abs(dlGrids{k}(:, 1:showSyms));
    
    imagesc(gridSlice);
    colormap(hot);
    xlabel('OFDM Symbol', 'FontSize', 10);
    ylabel('Subcarrier', 'FontSize', 10);
    title(sprintf('DL Grid — SCS %d kHz (2 slots)', scsValues(k)), 'FontSize', 11);
    set(gca, 'FontSize', 9);
end
sgtitle('PDSCH Resource Grid — First 2 Slots per SCS', 'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase3_resource_grids.png'));
fprintf('  Saved: phase3_resource_grids.png\n');

%% =====================================================================
%  SECTION 6: WAVEFORM SUMMARY TABLE
%  =====================================================================
fprintf('\n--- Section 6: Waveform Summary ---\n');

fprintf('  %-8s | %-12s | %-12s | %-10s | %-10s | %-10s\n', ...
    'SCS', 'DL Samples', 'UL Samples', 'DL SR', 'DL TBS', 'UL TBS');
fprintf('  %s\n', repmat('-', 1, 75));
for k = 1:nSCS
    fprintf('  %-8d | %-12d | %-12d | %7.2f MHz | %6d bits | %6d bits\n', ...
        scsValues(k), length(dlWaveforms{k}), length(ulWaveforms{k}), ...
        dlOfdmInfo{k}.SampleRate/1e6, dlTBS(k), ulTBS(k));
end

% Compute theoretical peak throughput per SCS
fprintf('\n  Theoretical Peak Throughput (single layer, 16QAM, rate 0.5):\n');
for k = 1:nSCS
    slotDur_s = 1e-3 / (2^(log2(scsValues(k)/15)));  % Slot duration in seconds
    slotsPerSec = 1 / slotDur_s;
    peakTput_Mbps = dlTBS(k) * slotsPerSec / 1e6;
    fprintf('    SCS %3d kHz: TBS=%6d bits/slot x %5.0f slots/s = %7.2f Mbps\n', ...
        scsValues(k), dlTBS(k), slotsPerSec, peakTput_Mbps);
end
fprintf('\n');

%% =====================================================================
%  SECTION 7: PASS WAVEFORMS THROUGH NTN CHANNEL (Preview)
%  =====================================================================
fprintf('--- Section 7: Channel preview (Suburban NTN-TDL-C) ---\n');

% Use the Suburban channel (NTN-TDL-C) as a representative preview
% Full channel simulation happens in Phase 4
suburbanIdx = 3;  % NTN-TDL-C
tdlChan = phase2.tdlChannels{suburbanIdx};

figure('Name', 'Channel Preview', 'Position', [100 100 1100 500]);

for k = 1:min(nSCS, 4)
    % Need to match channel sample rate to waveform sample rate
    chanPreview = nrTDLChannel;
    chanPreview.DelayProfile        = 'NTN-TDL-C';
    chanPreview.DelaySpread         = phase2.envConfigs(suburbanIdx).delaySpread;
    chanPreview.MaximumDopplerShift = phase2.mobileDoppler;
    chanPreview.SampleRate          = dlOfdmInfo{k}.SampleRate;
    chanPreview.NumTransmitAntennas = 1;
    chanPreview.NumReceiveAntennas  = 1;
    chanPreview.RandomStream        = params.channel.randomStream;
    chanPreview.Seed                = params.channel.seed;
    chanPreview.SatelliteDopplerShift = phase2.refSatDoppler;
    
    % Pass DL waveform through channel
    rxWaveform = chanPreview(dlWaveforms{k});
    
    % Compare spectra
    subplot(2, 2, k);
    sr = dlOfdmInfo{k}.SampleRate;
    nfft = 2048;
    [pxxTx, fTx] = pwelch(dlWaveforms{k}, hanning(nfft), nfft/2, nfft, sr, 'centered');
    [pxxRx, fRx] = pwelch(rxWaveform, hanning(nfft), nfft/2, nfft, sr, 'centered');
    
    plot(fTx/1e6, 10*log10(pxxTx/max(pxxTx)), 'b', 'LineWidth', 1.0);
    hold on;
    plot(fRx/1e6, 10*log10(pxxRx/max(pxxRx)), 'r', 'LineWidth', 1.0);
    hold off;
    xlabel('Freq (MHz)', 'FontSize', 10);
    ylabel('Norm. PSD (dB)', 'FontSize', 10);
    title(sprintf('SCS %d kHz — Before/After NTN-TDL-C', scsValues(k)), 'FontSize', 11);
    legend('Tx', 'Rx (NTN-TDL-C)', 'FontSize', 8, 'Location', 'southwest');
    grid on; set(gca, 'FontSize', 9); ylim([-60 5]);
end
sgtitle('Waveform Before/After NTN-TDL-C Suburban Channel', 'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase3_channel_preview.png'));
fprintf('  Saved: phase3_channel_preview.png\n');

%% =====================================================================
%  SECTION 8: VALIDATION CHECKS
%  =====================================================================
fprintf('\n--- Section 8: Validation checks ---\n');

% Check 1: DL waveforms generated for all SCS
fprintf('  [CHECK] DL waveforms generated: %d (expected %d)... ', ...
    sum(~cellfun(@isempty, dlWaveforms)), nSCS);
if sum(~cellfun(@isempty, dlWaveforms)) == nSCS, fprintf('PASS\n'); else, fprintf('FAIL\n'); end

% Check 2: UL waveforms generated for all SCS
fprintf('  [CHECK] UL waveforms generated: %d (expected %d)... ', ...
    sum(~cellfun(@isempty, ulWaveforms)), nSCS);
if sum(~cellfun(@isempty, ulWaveforms)) == nSCS, fprintf('PASS\n'); else, fprintf('FAIL\n'); end

% Check 3: Sample rate for 15 kHz SCS should be ~15.36 MHz for 52 RBs
dlSR15 = dlOfdmInfo{1}.SampleRate;
fprintf('  [CHECK] DL sample rate (15 kHz SCS) = %.2f MHz (expected ~15.36)... ', dlSR15/1e6);
if abs(dlSR15/1e6 - 15.36) < 1, fprintf('PASS\n'); else, fprintf('NOTE: %.2f MHz\n', dlSR15/1e6); end

% Check 4: 14 symbols per slot
nSymSlot = 14;
gridCols = size(dlGrids{1}, 2);
fprintf('  [CHECK] Grid columns (15 kHz, %d slots) = %d (expected %d)... ', ...
    numSlots, gridCols, numSlots * nSymSlot);
if gridCols == numSlots * nSymSlot, fprintf('PASS\n'); else, fprintf('WARNING\n'); end

% Check 5: TBS should be > 0 for all SCS
fprintf('  [CHECK] All DL TBS > 0... ');
if all(dlTBS > 0), fprintf('PASS (min=%d, max=%d bits)\n', min(dlTBS), max(dlTBS)); 
else, fprintf('FAIL\n'); end

fprintf('\n');

%% =====================================================================
%  SECTION 9: EXPORT RESULTS
%  =====================================================================
fprintf('--- Section 9: Exporting results ---\n');

phase3 = struct();

% SCS configuration
phase3.scsValues    = scsValues;
phase3.rbCounts     = rbCounts;
phase3.bwUsed_MHz   = bwUsed_MHz;
phase3.numSlots     = numSlots;

% Downlink waveforms and configs
phase3.dlWaveforms  = dlWaveforms;
phase3.dlGrids      = dlGrids;
phase3.dlCarriers   = dlCarriers;
phase3.dlPdschCfgs  = dlPdschCfgs;
phase3.dlOfdmInfo   = dlOfdmInfo;
phase3.dlTBS        = dlTBS;

% Uplink waveforms and configs
phase3.ulWaveforms  = ulWaveforms;
phase3.ulGrids      = ulGrids;
phase3.ulCarriers   = ulCarriers;
phase3.ulPuschCfgs  = ulPuschCfgs;
phase3.ulOfdmInfo   = ulOfdmInfo;
phase3.ulTBS        = ulTBS;

outFile = fullfile(params.outputDir, 'phase3_results.mat');
save(outFile, 'phase3', '-v7.3');
fprintf('  Saved: %s\n', outFile);

%% =====================================================================
%  SUMMARY
%  =====================================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 3 COMPLETE\n');
fprintf('============================================================\n');
fprintf('  Waveforms generated for %d SCS values: [', nSCS);
fprintf('%d ', scsValues);
fprintf('] kHz\n');
fprintf('  Downlink : CP-OFDM (nrPDSCH + nrOFDMModulate)\n');
fprintf('  Uplink   : DFT-s-OFDM (nrPUSCH + nrOFDMModulate, TransformPrecoding=true)\n');
fprintf('  Slots    : %d per SCS\n', numSlots);
fprintf('  Modulation: 16QAM, Code rate ~0.5\n');
fprintf('  Figures  : 4 (DL spectra, UL spectra, resource grids, channel preview)\n');
fprintf('\n  Load in Phase 4: load(''results/phase3_results.mat'')\n');
fprintf('============================================================\n');
