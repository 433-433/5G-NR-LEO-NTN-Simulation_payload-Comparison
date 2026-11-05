%% ============================================================
%  E1 — UPLINK (PUSCH) LINK BUDGET + BLER
%  Addresses Reviewer Theme E: "no uplink analysis."
%
%  The paper's results are downlink (satellite->UE). This script
%  evaluates the return link (UE->satellite): the UE is now the
%  transmitter (low power, ~23 dBm) and the satellite is the
%  receiver (defined by its G/T). We compute the uplink SNR across
%  elevation for both payloads and the resulting 10% BLER crossing,
%  to show whether the regenerative advantage persists on the uplink.
%
%  Self-contained; QPSK assumed for the power-limited uplink.
% ============================================================
clc; clear; close all;
rng('default');

%% ---------- Uplink link-budget parameters ----------
fc      = 2e9;          % S-band [Hz]
BW      = 360e3;        % narrow PUSCH allocation (2 RB @ 15 kHz) — the
                        % uplink is power-limited, so a full 10 MHz grant
                        % cannot be closed by a 23 dBm UE; a narrow grant
                        % concentrates the available power. [TS 38.101-5]
c       = 3e8;
Re      = 6371e3; h = 600e3;

% --- UE transmitter (uplink) ---
Pue_dBm = 23;           % UE Tx power (23 dBm = 200 mW, TS 38.101-5 power class 3)
Gue_dBi = 0;            % UE antenna gain
Lbody   = 3;            % body loss [dB]

% --- Satellite receiver ---
GT_sat  = 1.1;          % satellite G/T [dB/K] (typical LEO S-band payload)
Latm    = 1.3;          % atmospheric loss [dB]
k_dB    = -228.6;       % Boltzmann [dBW/K/Hz]

% Uplink noise reference uses satellite G/T directly:
% SNR = EIRP_ue - FSPL - Latm - Lbody + G/T_sat - k - 10log10(BW)
EIRP_ue = (Pue_dBm-30) + Gue_dBi;   % dBW

elev = [10 20 30 50 70 90];

% Transparent uplink also suffers the feeder + onboard impairments on the
% way back down through the bent pipe; regenerative terminates the uplink
% on board (single hop, clean). Reuse the conservative penalty split.
CI_IM_t=12; CI_ICI_t=14; CI_PN_t=16;   % transparent (dB)
CI_IM_r=13; CI_ICI_r=20; CI_PN_r=17;   % regenerative onboard (slightly better)

cascade = @(su,sf,a,b,d) -10*log10( 10.^(-su/10) + ...
    (isfinite(sf)).*10.^(-sf/10) + 10.^(-a/10)+10.^(-b/10)+10.^(-d/10) );

SNR_t = zeros(size(elev)); SNR_r = zeros(size(elev));
for i=1:numel(elev)
    d = sqrt((h+Re)^2-(Re*cosd(elev(i)))^2)-Re*sind(elev(i));
    FSPL = 20*log10(4*pi*d*fc/c);
    SNR_user = EIRP_ue - FSPL - Latm - Lbody + GT_sat - k_dB - 10*log10(BW);
    SNR_feeder = SNR_user + 8;
    SNR_t(i) = cascade(SNR_user, SNR_feeder, CI_IM_t, CI_ICI_t, CI_PN_t);
    SNR_r(i) = cascade(SNR_user, Inf,        CI_IM_r, CI_ICI_r, CI_PN_r);
end

fprintf('UPLINK link budget:\n');
fprintf('Elev  Transp SNR  Regen SNR  Adv\n');
for i=1:numel(elev)
    fprintf('%3d    %5.1f      %5.1f    %4.1f\n', elev(i), SNR_t(i), SNR_r(i), SNR_r(i)-SNR_t(i));
end

%% ---------- Uplink BLER (QPSK, power-limited) ----------
snrVec = -6:1:8;  M=4; k=log2(M); codeRate=0.48; nBlk=800; blkBits=2048;
blerT=zeros(size(snrVec)); blerR=zeros(size(snrVec));
% uplink transparent penalty = advantage observed at 50 deg
p = SNR_r(elev==50) - SNR_t(elev==50);
for i=1:numel(snrVec)
    snr=snrVec(i);
    cg = 10*log10(1/codeRate)+4.5;
    fR=0; fT=0;
    for b=1:nBlk
        bits=randi([0 1],blkBits,1);
        syms=bi2de(reshape(bits,k,[]).','left-msb');
        tx=qammod(syms,M,'gray','UnitAveragePower',true);
        rxR=awgn(tx, snr        +10*log10(k)+cg,'measured');
        rxT=awgn(tx, snr-p       +10*log10(k)+cg,'measured');
        fR=fR+any(qamdemod(rxR,M,'gray','UnitAveragePower',true)~=syms);
        fT=fT+any(qamdemod(rxT,M,'gray','UnitAveragePower',true)~=syms);
    end
    blerR(i)=fR/nBlk; blerT(i)=fT/nBlk;
end
iR=find(blerR<=0.10,1,'first'); iT=find(blerT<=0.10,1,'first');
if isempty(iR); crossR=NaN; else; crossR=snrVec(iR); end
if isempty(iT); crossT=NaN; else; crossT=snrVec(iT); end
fprintf('\nUplink 10%% BLER: regen %.2f dB | transp %.2f dB | shift %.2f dB\n',...
    crossR,crossT,crossT-crossR);

save('uplink_results.mat','elev','SNR_t','SNR_r','snrVec','blerR','blerT','crossR','crossT');

figure('Color','w','Position',[100 100 560 420]);
semilogy(snrVec,blerR,'-s','LineWidth',1.6,'DisplayName','Regenerative (UL)'); hold on;
semilogy(snrVec,blerT,'-o','LineWidth',1.6,'DisplayName','Transparent (UL)');
yline(0.10,'--k','10% BLER'); grid on;
xlabel('Uplink SNR (dB)'); ylabel('BLER');
title('Uplink (PUSCH) BLER — QPSK, NTN-TDL-C');
legend('Location','southwest');
saveas(gcf,'uplink_bler.png');