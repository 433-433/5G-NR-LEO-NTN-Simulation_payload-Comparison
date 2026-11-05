function tx = applyImpairments(tx, prof, pnObj, fs)
%APPLYIMPAIRMENTS  Inject Route-A physical impairments into a TX waveform.
%   tx   : complex baseband waveform (column vector)
%   prof : payload impairment profile — fields:
%            .name              label, string
%            .hpaIBO_dB         input back-off of the first HPA (gateway/onboard) [dB]
%            .hpaCascade        true -> apply a second (satellite transponder) HPA
%            .hpaIBO2_dB        input back-off of the second HPA (if hpaCascade)
%            .hpaSmoothness     Rapp p-factor (SSPA typical 2-3)
%            .hpaSatLevel       normalised saturation amplitude (1.0)
%            .cfo_Hz            residual carrier frequency offset [Hz]
%   pnObj: pre-configured comm.PhaseNoise object for this profile (BOTH payloads
%          get phase noise, but at different levels)
%   fs   : sample rate [Hz]
%
%   This replaces the previous "snrDegradation = ...; snr - snrDegradation" shift
%   with the real waveform-level operations the two reviewers asked for.

    tx = hpaRapp(tx, prof.hpaIBO_dB, prof.hpaSmoothness, prof.hpaSatLevel);
    if isfield(prof,'hpaCascade') && prof.hpaCascade
        tx = hpaRapp(tx, prof.hpaIBO2_dB, prof.hpaSmoothness, prof.hpaSatLevel);
    end
    tx = pnObj(tx);
    t  = (0:size(tx,1)-1).'/fs;
    tx = tx .* exp(1j*2*pi*prof.cfo_Hz*t);
end

% ------------------------------------------------------------------------
function y = hpaRapp(x, IBO_dB, p, Asat)
%HPARAPP  Memoryless Rapp SSPA model. Larger input back-off (IBO) means less
%   drive relative to saturation, so lower intermodulation and a higher C/I.
%   Average power is restored after clipping so the operating SNR definition
%   is preserved and distortion appears as an in-band noise/C-I floor.
    x = x(:);
    Prms  = sqrt(mean(abs(x).^2)) + eps;
    scale = Asat / (Prms * 10^(IBO_dB/20));   % drive so rms sits IBO dB below sat
    xin = x * scale;
    a   = abs(xin);
    g   = 1 ./ (1 + (a./Asat).^(2*p)).^(1/(2*p));   % Rapp AM/AM, ~0 AM/PM
    y   = (xin .* g) / scale;
end
