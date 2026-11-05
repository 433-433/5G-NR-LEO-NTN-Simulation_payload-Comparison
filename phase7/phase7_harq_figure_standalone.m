%% ========================================================================
%  STANDALONE HARQ IMPACT FIGURE (corrected framing)
%  ========================================================================
%  Builds fig_harq_impact.png from the saved BLER-CI results (real curves),
%  with the corrected Theme C framing: both payloads can run HARQ under
%  Release 17's 32 processes; the distinction is pipeline depth
%  (~34 vs ~24 processes), NOT "HARQ disabled".
%
%  Requires phase7_bler_ci.mat (produced by the confidence-interval run),
%  which contains snrRange, mR (regen mean BLER), mT (transp mean BLER).
%  If that file is missing, set the fallback path or re-run the CI script.
% ========================================================================
clc; clear; close all;

% --- Load the real BLER curves from the CI run ---
matPath = 'results/phase7_bler_ci.mat';        % adjust if needed
if ~isfile(matPath)
    % try current folder
    if isfile('phase7_bler_ci.mat'); matPath = 'phase7_bler_ci.mat';
    else
        error(['phase7_bler_ci.mat not found. Run the confidence-interval ' ...
               'script first, or set matPath to its location.']);
    end
end
S = load(matPath);            % expects snrRange, mR, mT
snrRange = S.snrRange;
bler_regen  = S.mR;           % regenerative mean BLER
bler_transp = S.mT;           % transparent mean BLER

% --- HARQ chase-combining model (per retransmission ~ BLER^(k+1)) ---
bler_regen_h1 = bler_regen .* bler_regen;         % regen + 1 retx
bler_regen_h2 = bler_regen_h1 .* bler_regen;      % regen + 2 retx
bler_transp_h1 = bler_transp .* bler_transp;      % transp + 1 retx (ideal)

figure('Name','HARQ Impact','Position',[100 100 1000 450]);

% Left: regenerative, operating within the 32-process ceiling
subplot(1,2,1);
semilogy(snrRange, bler_regen,    '-bs','LineWidth',2,'MarkerSize',5, ...
    'DisplayName','Regenerative (1st Tx)'); hold on;
semilogy(snrRange, bler_regen_h1, '-g^','LineWidth',1.5,'MarkerSize',4, ...
    'DisplayName','Regen + 1 HARQ retx');
semilogy(snrRange, bler_regen_h2, '-md','LineWidth',1.5,'MarkerSize',4, ...
    'DisplayName','Regen + 2 HARQ retx');
yl1 = yline(0.1,'--k','10% BLER','LineWidth',1); yl1.HandleVisibility='off';
hold off; grid on; ylim([1e-4 1]);
xlabel('SNR (dB)','FontSize',11); ylabel('BLER','FontSize',11);
title('Regenerative — HARQ Combining (\sim24 proc.)','FontSize',12);
legend('Location','southwest','FontSize',8); set(gca,'FontSize',10);

% Right: transparent, deeper pipeline exceeding the ceiling at low elev.
subplot(1,2,2);
semilogy(snrRange, bler_transp,    '-ro','LineWidth',2,'MarkerSize',5, ...
    'DisplayName','Transparent (1st Tx)'); hold on;
semilogy(snrRange, bler_transp_h1, '--r^','LineWidth',1.2,'MarkerSize',4, ...
    'DisplayName','Transp + 1 retx (ideal)');
yl2 = yline(0.1,'--k','10% BLER','LineWidth',1); yl2.HandleVisibility='off';
text(mean(snrRange), 0.5, 'Pipeline \sim34 proc.', 'FontSize',12, ...
    'HorizontalAlignment','center','Color',[0.7 0 0],'FontWeight','bold');
text(mean(snrRange), 0.28, 'exceeds 32-proc. cap at low elev.', 'FontSize',9, ...
    'HorizontalAlignment','center','Color',[0.5 0 0]);
hold off; grid on; ylim([1e-4 1]);
xlabel('SNR (dB)','FontSize',11); ylabel('BLER','FontSize',11);
title('Transparent — Deeper HARQ Pipeline','FontSize',12);
legend('Location','southwest','FontSize',8); set(gca,'FontSize',10);

sgtitle('HARQ Impact — Regenerative vs Transparent Pipeline Depth', ...
    'FontSize',13,'FontWeight','bold');

outDir = fileparts(matPath); if isempty(outDir); outDir = '.'; end
saveas(gcf, fullfile(outDir,'fig_harq_impact.png'));
fprintf('Saved: %s\n', fullfile(outDir,'fig_harq_impact.png'));
