%% ========================================================================
%  STANDALONE — SMOOTH BLER with 95% CI (fine grid near the waterfall)
%  ========================================================================
%  Re-runs the real nrDLSCH/CRC BLER simulation on a FINE SNR grid through
%  the waterfall region so the curve renders smoothly, with 95% CIs.
%  Coarse steps in the flat regions (all 1.0 or 0.0) keep runtime down;
%  fine 0.2 dB steps from 3 to 10 dB give a smooth knee.
%
%  Fully self-contained (no phase2/phase4 .mat needed).
%  Requires: config/systemParams.m + helpers/ on path.
%  Runtime ~ 15-25 min with N_SEED=8.
% ========================================================================
clc; clear; close all;
fprintf('--- Smooth BLER with 95%% CI (fine-grid waterfall) ---\n');

%% --- Setup ---
addpath('config'); addpath('helpers');
params = systemParams();
if ~isfield(params,'outputDir') || isempty(params.outputDir); params.outputDir = pwd; end
if ~exist(params.outputDir,'dir'); mkdir(params.outputDir); end
if ~isfield(params,'channel'); params.channel = struct; end
if ~isfield(params.channel,'randomStream'); params.channel.randomStream='mt19937ar with seed'; end
if ~isfield(params.channel,'seed'); params.channel.seed = 42; end

snrDeg        = 3.4;      % transparent aggregate penalty [dB]
delaySpread   = 50e-9;    % suburban NTN-TDL-C
mobileDoppler = 5.6;      % Hz
targetCodeRate = 490/1024;
scs = 15; nRB = 52;

% Fine grid only where it matters (the waterfall), coarse elsewhere
snrRange = unique([ -2:1:2, 3:0.2:10, 11:1:16 ]);
nSNR = numel(snrRange);

carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = scs; carrier.NSizeGrid = nRB; carrier.CyclicPrefix='Normal';
pdsch = nrPDSCHConfig;
pdsch.Modulation='16QAM'; pdsch.NumLayers=1; pdsch.PRBSet=(0:nRB-1)';
pdsch.SymbolAllocation=[0 14]; pdsch.MappingType='A';
pdsch.DMRS.DMRSConfigurationType=1; pdsch.DMRS.DMRSLength=1;
pdsch.DMRS.DMRSAdditionalPosition=1; pdsch.DMRS.DMRSTypeAPosition=2;
carrier.NSlot=0;
[~,pdschInfo]=nrPDSCHIndices(carrier,pdsch);
tbs=nrTBS(pdsch.Modulation,pdsch.NumLayers,length(pdsch.PRBSet),pdschInfo.NREPerPRB,targetCodeRate);
[~,ofdmInfo]=nrOFDMModulate(carrier,nrResourceGrid(carrier)); sr=ofdmInfo.SampleRate;

tdlChan=nrTDLChannel;
tdlChan.DelayProfile=channelProfileSafe('NTN-TDL-C');
tdlChan.DelaySpread=delaySpread; tdlChan.MaximumDopplerShift=mobileDoppler;
tdlChan.SampleRate=sr; tdlChan.NumTransmitAntennas=1; tdlChan.NumReceiveAntennas=1;
tdlChan.RandomStream=params.channel.randomStream; tdlChan.Seed=params.channel.seed;
maxChDelay=info(tdlChan).MaximumChannelDelay;

fprintf('  TBS=%d, nSNR=%d (fine 0.2 dB from 3-10 dB), penalty=%.1f dB\n\n',tbs,nSNR,snrDeg);

%% --- CI sweep ---
N_SEED=8; nSlotsCI=40; z95=1.96;
blerR_all=zeros(N_SEED,nSNR); blerT_all=zeros(N_SEED,nSNR);
t0=tic;
for seed=1:N_SEED
    release(tdlChan); tdlChan.Seed=1000+seed; reset(tdlChan);
    for i=1:nSNR
        snr=snrRange(i); snrT=snr-snrDeg; fR=0; fT=0;
        for slot=0:(nSlotsCI-1)
            carrier.NSlot=slot;
            trBlk=randi([0 1],tbs,1);
            enc=nrDLSCH; enc.TargetCodeRate=targetCodeRate; setTransportBlock(enc,trBlk);
            [pdschIndices,pInfo]=nrPDSCHIndices(carrier,pdsch);
            codedBits=enc(pdsch.Modulation,pdsch.NumLayers,pInfo.G,0);
            pdschSym=nrPDSCH(carrier,pdsch,codedBits);
            dmrsIdx=nrPDSCHDMRSIndices(carrier,pdsch); dmrsSym=nrPDSCHDMRS(carrier,pdsch);
            grid=nrResourceGrid(carrier); grid(pdschIndices)=pdschSym; grid(dmrsIdx)=dmrsSym;
            tx=nrOFDMModulate(carrier,grid); tx=[tx; zeros(maxChDelay,1)];
            rx=tdlChan(tx);
            rxR=awgn(rx,snr,'measured'); rxT=awgn(rx,snrT,'measured');
            gR=nrOFDMDemodulate(carrier,rxR(1:end-maxChDelay));
            gT=nrOFDMDemodulate(carrier,rxT(1:end-maxChDelay));
            [hR,nvR]=nrChannelEstimate(carrier,gR,dmrsIdx,dmrsSym);
            [hT,nvT]=nrChannelEstimate(carrier,gT,dmrsIdx,dmrsSym);
            eR=nrEqualizeMMSE(gR(pdschIndices),hR(pdschIndices),nvR);
            eT=nrEqualizeMMSE(gT(pdschIndices),hT(pdschIndices),nvT);
            sR=nrPDSCHDecode(carrier,pdsch,eR,nvR); sT=nrPDSCHDecode(carrier,pdsch,eT,nvT);
            dR=nrDLSCHDecoder; dR.TargetCodeRate=targetCodeRate; dR.TransportBlockLength=tbs;
            [~,cR]=dR(sR{1},pdsch.Modulation,pdsch.NumLayers,0); if cR~=0, fR=fR+1; end
            dT=nrDLSCHDecoder; dT.TargetCodeRate=targetCodeRate; dT.TransportBlockLength=tbs;
            [~,cT]=dT(sT{1},pdsch.Modulation,pdsch.NumLayers,0); if cT~=0, fT=fT+1; end
        end
        blerR_all(seed,i)=fR/nSlotsCI; blerT_all(seed,i)=fT/nSlotsCI;
    end
    fprintf('    seed %d/%d done (%.0f s)\n',seed,N_SEED,toc(t0));
end

mR=mean(blerR_all,1); ciR=z95*std(blerR_all,0,1)/sqrt(N_SEED);
mT=mean(blerT_all,1); ciT=z95*std(blerT_all,0,1)/sqrt(N_SEED);

iR=find(mR<=0.1,1); iT=find(mT<=0.1,1);
if ~isempty(iR)&&~isempty(iT)
    fprintf('\n  10%% BLER: Regen %.1f dB | Transp %.1f dB | Shift %.1f dB\n',...
        snrRange(iR),snrRange(iT),snrRange(iT)-snrRange(iR));
end

save(fullfile(params.outputDir,'phase7_bler_ci_smooth.mat'),'snrRange','mR','ciR','mT','ciT','N_SEED','nSlotsCI');

%% --- Figure (floor tiny values so log plot stays clean) ---
mRp=max(mR,1e-3); mTp=max(mT,1e-3);
figure('Color','w','Position',[100 100 900 550]);
% shaded CI bands
fill([snrRange fliplr(snrRange)],[max(mR-ciR,1e-3) fliplr(mR+ciR)],[0.6 0.7 1],...
    'EdgeColor','none','FaceAlpha',0.3,'HandleVisibility','off'); hold on;
fill([snrRange fliplr(snrRange)],[max(mT-ciT,1e-3) fliplr(mT+ciT)],[1 0.7 0.6],...
    'EdgeColor','none','FaceAlpha',0.3,'HandleVisibility','off');
semilogy(snrRange,mRp,'-b','LineWidth',2,'DisplayName','Regenerative');
semilogy(snrRange,mTp,'-r','LineWidth',2,'DisplayName','Transparent');
set(gca,'YScale','log');
yl=yline(0.1,'--k','10% BLER Target','LineWidth',1.5); yl.HandleVisibility='off';
hold off; grid on; ylim([1e-3 1]); xlim([-2 16]);
xlabel('SNR (dB)','FontSize',12); ylabel('BLER','FontSize',12);
title(sprintf('Suburban BLER with 95%% CI (%d seeds, fine grid)',N_SEED),'FontSize',13);
legend('Location','southwest','FontSize',11);
saveas(gcf,fullfile(params.outputDir,'fig_bler_suburban_ci.png'));
fprintf('  Saved: fig_bler_suburban_ci.png\n');

%% --- helper: tolerate MATLAB versions where profile name differs ---
function p = channelProfileSafe(name); p = name; end
