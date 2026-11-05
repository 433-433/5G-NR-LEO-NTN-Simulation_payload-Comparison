%% ========================================================================
%  REPLACEMENT for Figure 4 in phase7_reliability.m Section 5
%  ========================================================================
%  The original right-hand subplot printed "HARQ DISABLED (RTT exceeds
%  timer)", which contradicts the corrected Theme C framing (Release 17
%  gives 32 HARQ processes to BOTH payloads; the real distinction is
%  pipeline depth, not disabling). This replacement re-labels the panel
%  accordingly.
%
%  Replace the block starting at "% ---- Figure 4:" through its saveas()
%  line with the following.
% ========================================================================

% ---- Figure 4: BLER Comparison with HARQ Pipeline Note ----
figure('Name', 'BLER HARQ', 'Position', [100 100 1000 550]);

subplot(1, 2, 1);
semilogy(snrRange, bler_regen, '-bs', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Regenerative (1st Tx)');
hold on;
bler_harq1 = bler_regen .* bler_regen;   % after 1 retransmission (chase comb.)
bler_harq2 = bler_harq1 .* bler_regen;   % after 2 retransmissions
semilogy(snrRange, bler_harq1, '-g^', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Regen + 1 HARQ retx');
semilogy(snrRange, bler_harq2, '-md', 'LineWidth', 1.5, 'MarkerSize', 4, ...
    'DisplayName', 'Regen + 2 HARQ retx');
yline(0.1, '--k', '10% BLER', 'LineWidth', 1);
yline(0.01, ':k', '1% BLER', 'LineWidth', 1);
hold off;
xlabel('SNR (dB)', 'FontSize', 11); ylabel('BLER', 'FontSize', 11);
title('Regenerative — HARQ Combining (\sim24 proc.)', 'FontSize', 12);
legend('Location', 'southwest', 'FontSize', 8);
grid on; set(gca, 'FontSize', 10); ylim([1e-4 1]);

subplot(1, 2, 2);
semilogy(snrRange, bler_transp, '-ro', 'LineWidth', 2, 'MarkerSize', 5, ...
    'DisplayName', 'Transparent (1st Tx)');
hold on;
% Transparent CAN combine, but its deeper pipeline (~34 proc) exceeds the
% Rel-17 32-process ceiling at low elevation, so gains are only partially
% realizable there. Show the ideal combining as a dashed reference.
bler_harq1_T = bler_transp .* bler_transp;
semilogy(snrRange, bler_harq1_T, '--r^', 'LineWidth', 1.2, 'MarkerSize', 4, ...
    'DisplayName', 'Transp + 1 retx (ideal)');
yline(0.1, '--k', '10% BLER', 'LineWidth', 1);
yline(0.01, ':k', '1% BLER', 'LineWidth', 1);
text(mean(snrRange), 0.5, 'Pipeline \sim34 proc.', 'FontSize', 12, ...
    'HorizontalAlignment', 'center', 'Color', [0.7 0 0], 'FontWeight', 'bold');
text(mean(snrRange), 0.28, 'exceeds 32-proc. cap at low elev.', 'FontSize', 9, ...
    'HorizontalAlignment', 'center', 'Color', [0.5 0 0]);
hold off;
xlabel('SNR (dB)', 'FontSize', 11); ylabel('BLER', 'FontSize', 11);
title('Transparent — Deeper HARQ Pipeline', 'FontSize', 12);
legend('Location', 'southwest', 'FontSize', 8);
grid on; set(gca, 'FontSize', 10); ylim([1e-4 1]);

sgtitle('HARQ Impact — Regenerative vs Transparent Pipeline Depth', ...
    'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, fullfile(params.outputDir, 'phase7_bler_harq.png'));
fprintf('  Saved: phase7_bler_harq.png (corrected HARQ framing)\n');
