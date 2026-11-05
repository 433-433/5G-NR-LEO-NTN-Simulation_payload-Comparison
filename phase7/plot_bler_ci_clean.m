%% ========================================================================
%  make_bler_figure.m  —  CLEAN BLER-with-95%-CI figure (runs in seconds)
%  ========================================================================
%  Answers Reviewer E (confidence intervals). Loads your REAL saved CI data
%  and renders a publication-clean figure:
%     - shaded 95% CI bands
%     - smooth shape-preserving curve through the REAL measured points
%     - real points shown as open markers (nothing invented)
%     - 10% BLER target line + a double-arrow marking the dB shift
%  No simulation. No toolbox tricks. Saves fig_bler_suburban_ci.png
%  (the exact filename the paper references).
% ========================================================================
clc; clear; close all;

% ---- 1. locate the real CI results file ----
cand = {'results/phase7_bler_ci.mat','phase7_bler_ci.mat', ...
        'results/phase7_bler_ci_smooth.mat','phase7_bler_ci_smooth.mat'};
matPath = '';
for k = 1:numel(cand)
    if isfile(cand{k}); matPath = cand{k}; break; end
end
if isempty(matPath)
    error(['No phase7_bler_ci*.mat found in this folder or .\\results. ' ...
           'Run your confidence-interval script first.']);
end
S = load(matPath);

% ---- 2. pull vectors, tolerate either naming ----
snr = S.snrRange(:).';
mR  = S.mR(:).';   mT  = S.mT(:).';
if isfield(S,'ciR'); ciR = S.ciR(:).'; else; ciR = zeros(size(mR)); end
if isfield(S,'ciT'); ciT = S.ciT(:).'; else; ciT = zeros(size(mT)); end
fprintf('Loaded %s  (%d SNR points)\n', matPath, numel(snr));

fl = 1e-3;                          % display floor for the log axis
mRp = max(mR,fl);  mTp = max(mT,fl);

% ---- 3. smooth curve through the REAL points (shape-preserving) ----
snrF = linspace(min(snr), max(snr), 400);
mRf  = max(pchip(snr, mRp, snrF), fl);
mTf  = max(pchip(snr, mTp, snrF), fl);

% ---- 4. 10% crossings from the real points ----
iR = find(mR <= 0.1, 1, 'first');   xR = snr(iR);   % may be empty-safe below
iT = find(mT <= 0.1, 1, 'first');   xT = snr(iT);
haveCross = ~isempty(iR) && ~isempty(iT);

% ---- 5. plot ----
figure('Color','w','Position',[100 100 900 550]); hold on;

% CI bands
fill([snr fliplr(snr)], [max(mR-ciR,fl) fliplr(mR+ciR)], [0.30 0.45 0.85], ...
     'EdgeColor','none','FaceAlpha',0.20,'HandleVisibility','off');
fill([snr fliplr(snr)], [max(mT-ciT,fl) fliplr(mT+ciT)], [0.85 0.30 0.25], ...
     'EdgeColor','none','FaceAlpha',0.20,'HandleVisibility','off');

% smooth lines
plot(snrF, mRf, '-', 'Color',[0.16 0.31 0.82], 'LineWidth',2.4, 'DisplayName','Regenerative');
plot(snrF, mTf, '-', 'Color',[0.82 0.20 0.16], 'LineWidth',2.4, 'DisplayName','Transparent');

% real measured points
plot(snr, mRp, 'o', 'Color',[0.16 0.31 0.82], 'MarkerFaceColor','w', 'MarkerSize',5, 'HandleVisibility','off');
plot(snr, mTp, 'o', 'Color',[0.82 0.20 0.16], 'MarkerFaceColor','w', 'MarkerSize',5, 'HandleVisibility','off');

set(gca,'YScale','log');
yl = yline(0.1,'--k','10% BLER Target','LineWidth',1.4);
yl.HandleVisibility = 'off';

% double-arrow marking the shift (drawn in DATA coordinates, always centred)
if haveCross
    plot(xR,0.1,'o','Color',[0.16 0.31 0.82],'MarkerFaceColor',[0.16 0.31 0.82],'MarkerSize',8,'HandleVisibility','off');
    plot(xT,0.1,'o','Color',[0.82 0.20 0.16],'MarkerFaceColor',[0.82 0.20 0.16],'MarkerSize',8,'HandleVisibility','off');
    yA = 0.19; dx = 0.18*(xT-xR);
    plot([xR xT],[yA yA],'-','Color',[.25 .25 .25],'LineWidth',1.3,'HandleVisibility','off');
    plot([xR xR+dx],[yA yA*1.18],'-','Color',[.25 .25 .25],'LineWidth',1.3,'HandleVisibility','off');
    plot([xR xR+dx],[yA yA/1.18],'-','Color',[.25 .25 .25],'LineWidth',1.3,'HandleVisibility','off');
    plot([xT xT-dx],[yA yA*1.18],'-','Color',[.25 .25 .25],'LineWidth',1.3,'HandleVisibility','off');
    plot([xT xT-dx],[yA yA/1.18],'-','Color',[.25 .25 .25],'LineWidth',1.3,'HandleVisibility','off');
    text(mean([xR xT]), yA*1.6, sprintf('%.1f dB shift', xT-xR), ...
         'HorizontalAlignment','center','FontSize',10,'Color',[.2 .2 .2]);
end

grid on; set(gca,'FontSize',11);
ylim([fl 1.3]); xlim([min(snr) max(snr)]);
xlabel('SNR (dB)','FontSize',12); ylabel('BLER','FontSize',12);
title('Suburban (NTN-TDL-C) BLER with 95% CI','FontSize',13);
legend('Location','southwest','FontSize',11);
hold off;

% ---- 6. save with the exact filename the paper references ----
outDir = fileparts(matPath); if isempty(outDir); outDir = '.'; end
outFile = fullfile(outDir,'fig_bler_suburban_ci.png');
saveas(gcf, outFile);
fprintf('Saved: %s\n', outFile);
if haveCross
    fprintf('10%% BLER crossings (real data): Regen %.1f dB | Transp %.1f dB | Shift %.1f dB\n', ...
        xR, xT, xT-xR);
end