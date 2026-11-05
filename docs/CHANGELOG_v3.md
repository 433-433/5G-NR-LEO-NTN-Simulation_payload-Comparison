# Phase 4/6/7 v3 — Route A drop-ins

These three files are drop-in replacements that plug into your existing
`config/systemParams.m` + `helpers/` + `results/` pipeline, so you keep
Phases 1–3 and 5 unchanged.

## What they fix

**Phase 4 (`phase4_v3.m`)** keeps the per-elevation thermal link budget (that
part of your Phase 4 was fine). It removes:

- the hardcoded `snr_intermod_dB = 12 / snr_ICI_dB = 14 / snr_phaseNoise_dB = 16`
  stack that was applied **only** to transparent (Reviewer #1: these affect
  both payloads);
- the exported scalar `phase4.snrDegradation` that was the shift Phases 6/7
  then used;
- the Section 6 BER preview that applied the shift.

In their place it exports a **physical impairment profile** (HPA back-off,
oscillator phase-noise level, residual CFO per payload) and a **per-elevation
feederPenalty_dB** vector derived from the actual user+feeder cascade
formula. Reference residual CFO is **200 Hz** (±0.1 ppm at 2 GHz,
TS 38.101-5), replacing the inflated 1–2 kHz you had.

**Phase 6 (`phase6_v3.m`)** removes the smoking-gun lines:

```matlab
snrDeg = phase4.snrDegradation;
snr_transp_dB = snr_dB - snrDeg;
rxRegen  = awgn(rxWaveform, snr_dB,        'measured');
rxTransp = awgn(rxWaveform, snr_transp_dB, 'measured');   % same rxWaveform
```

and replaces them with per-payload impairment injection into the TX
waveform *before* the channel, same channel realisation for both payloads
(seed-locked per slot). Transparent AWGN power is `SNR − feederPenalty_dB`,
not `SNR − snrDegradation`. The invalid 120 kHz FR1 case is dropped; the
sweep now covers `[15, 30, 60]` kHz, all 10 MHz FR1.

**Phase 7 (`phase7_v3.m`)** does the same waveform-level injection for BLER,
and additionally:

- replaces the fake `bler_harq1 = bler_regen .* bler_regen` with real
  incremental-redundancy HARQ using the `nrDLSCHDecoder` soft buffer across
  the RV sequence `[0 2 3 1]` — this directly answers the
  "BLER^(k+1) ignores combining gain" complaint;
- runs HARQ for BOTH payloads (Rel-17 feasibility — K_offset, extended K1,
  32 HARQ processes);
- removes the baked "HARQ DISABLED (RTT exceeds timer)" text;
- simulates NTN-TDL-C **and** NTN-TDL-D so Fig 7 (rural worse than suburban)
  can be diagnosed properly;
- bumps blocks/point via `seeds = [73 101 202 303]` and 95% CI bands so the
  "0.053 ≈ 1/19" quantised-floor artefact is gone.

## File layout to drop into your project

```
<project root>/
  config/                       ← unchanged
    systemParams.m
  helpers/                      ← add these two files
    applyImpairments.m          ← NEW (TX-side HPA/PN/CFO injection)
    firstCrossing.m             ← NEW (log-interpolated 10% crossing)
    computeSlantRange.m         ← keep yours
  phase1_scenario.m             ← unchanged (phase1_v2 is fine)
  phase2_...                    ← unchanged (whatever you have)
  phase3_...                    ← unchanged
  phase4_v3.m                   ← NEW (replaces phase4_payload.m)
  phase5_...                    ← unchanged
  phase6_v3.m                   ← NEW (replaces phase6_throughput.m)
  phase7_v3.m                   ← NEW (replaces phase7_reliability.m)
```

The v3 files write their outputs to the same `results/phase4_results.mat`,
`phase6_results.mat`, `phase7_results.mat` filenames your pipeline already
uses, so Phase 5 and any plotting scripts you have keep working — EXCEPT any
code that reads `phase4.snrDegradation`. That field is intentionally gone;
Phases 6/7 v3 assert against it, and legacy code reading it will fail loudly
(which is the point).

## Run order

```matlab
phase4_v3         % few seconds
phase6_v3         % minutes
phase7_v3         % longer (two environments + HARQ sweep + multi-MCS)
```

Then **send me back** everything in your `results/` folder from these three
runs (`phase4_results.mat`, `phase6_results.mat`, `phase7_results.mat` plus
the `.png`s with the `_v3_` prefix). I wire the measured numbers into the
paper — I will not invent any figure.

## Expect a smaller gap than 3.4 dB

With impairments now symmetric (both payloads see the HPA/PN/CFO your
reviewers insisted on) and residual CFO set to the spec-compliant 200 Hz,
the measured 10%-BLER gap will likely come out **smaller** than the old
3.4 dB. That is the correct physics and a *stronger* paper — the penalty
will now rest on feeder-link noise and transponder nonlinearity
(defensible) rather than an inflated Doppler ICI term (what Reviewer #1
flagged). Whatever the sim says, that is the number we report.

If you want a larger measured gap, justify it physically by **documenting**
a lower satellite-HPA back-off (`imp.hpa.IBO_satellite_dB`), a worse
transponder phase-noise mask (`imp.pn.level_dBc_transp`), or a higher
feeder penalty from the (new) feeder-link parameter table the reviewers
asked for — do **not** go back to hardcoding a C/I value.

## Known pitfalls already handled

- `release(tdl)` before every re-seed so the Seed property can be changed.
- `firstCrossing` instead of `interp1` on flat BLER segments.
- `if iscell(llr); llr = llr{1}; end` for 1-codeword compatibility across
  5G Toolbox versions.
- Both payloads see the SAME channel realisation per slot (seed-locked),
  so the gap comes from pre-channel impairments only — no accidental
  randomness.
- 0.5 dB SNR grid near waterfall; blocks/point tracked and shown in the
  validation check.

## Camera-ready run

Raise `nSlots` to 200 in `phase7_v3.m` (so `nSlots*numel(seeds) = 800`
blocks per point); the waterfalls will be smooth and the CI bands tight.

## Still to come (next deliverables)

End-to-end latency with the feeder hop; the HARQ pipeline-depth figure for
the paper text; new Ghana coverage-time / elevation-CDF figures; citation
verification (Lin, MDPI Network 2025, Nature 2026, Meshram — I verify
before adding, not fabricate); and the point-by-point response-to-reviewers
letter. Those come after you send the sim outputs — and I still need the
**revision deadline** to scope how much re-simulation to attempt.
