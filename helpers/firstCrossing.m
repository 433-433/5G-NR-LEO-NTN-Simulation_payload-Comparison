function xc = firstCrossing(snr, bler, target)
%FIRSTCROSSING  First SNR at which BLER falls below `target`, interpolated
%   in log-BLER between the two straddling points. Monotone-safe; avoids the
%   "interp1 sample points must be unique" error that flat BLER segments cause.
    idx = find(bler <= target, 1, 'first');
    if isempty(idx); xc = NaN; return; end
    if idx == 1;    xc = snr(1); return; end
    x1 = snr(idx-1); x2 = snr(idx);
    y1 = log10(max(bler(idx-1), 1e-6));
    y2 = log10(max(bler(idx),   1e-6));
    yt = log10(target);
    xc = x1 + (yt - y1)*(x2 - x1)/(y2 - y1);
end
