# Performance Analysis of 5G NR in LEO Non-Terrestrial Networks

**A Physics-Based Comparative Study of Transparent and Regenerative Payload Architectures**

> MATLAB simulation code accompanying the ICAST 2026 paper (Paper ID 110).
> Waveform-level 5G NR PDSCH chain with Rapp SSPA, oscillator phase noise, spec-compliant CFO and feeder-link noise — run twice, once with the full transparent-payload impairment stack and once with a clean regenerative payload — to measure the 10 % BLER gap from physics instead of from closed-form C/I assumptions.

---

## Headline result

| | Regenerative (Rel-19) | Transparent (Rel-17) |
|---|---|---|
| SNR at 10 % BLER, suburban (NTN-TDL-C), 16QAM R = 0.48 | **9.62 dB** | **11.11 dB** |
| **Measured gap** | | **1.48 dB** |

The 1.48 dB penalty is dominated by the on-satellite HPA (≈ 1.00 dB); phase noise, residual CFO and feeder-link noise together account for less than 0.5 dB.

---

## Authors

- **Lawerteh Isaiah Amatey** — Teaching & Research Assistant, KNUST · isaiahanim20@gmail.com
- **Davies Kojo Egyir**
- **Kelvin Asante Obeng**
- **Clement Heanampong**
- **Prof. James Dzisi Gadze** — supervisor

*Department of Telecommunications Engineering, Kwame Nkrumah University of Science and Technology (KNUST), Kumasi, Ghana.*

---

## Project structure

The code is organised as a sequence of **phases**. Each phase has its own folder with the same internal layout:

```
<phase>/
  config/systemParams.m        ← system-level parameter sheet (consistent across all phases)
  helpers/                     ← local helpers used by this phase
  <phase>_<topic>.m            ← the main script that runs this phase
  results/                     ← .mat state and .png figures written by the script
```

Phases **4, 6 and 7** have `*_v3.m` drop-in replacements at the repository root — these are the current, reviewer-compliant versions (see `docs/CHANGELOG_v3.md` for what they fix and why).

### Phase map

| Phase | Script | What it does |
|---|---|---|
| **1** | `phase1_v2/phase1_scenario.m` | Walker Delta 72/6/1 constellation at 600 km over Ghana — orbital propagation, elevation CDF, visibility, handovers, Doppler, FSPL. |
| **2** | `phase2/phase2_channel.m` | NTN-TDL-C (suburban) and NTN-TDL-D (rural) channel model generation, power-delay profiles, P.681 fading preview. |
| **3** | `phase3/phase3_waveform.m` | 5G NR PDSCH waveform generation (TB → LDPC → PDSCH mapping → OFDM modulator), resource grids, spectra. |
| **4** | `phase4_v3.m` (replaces `phase4/phase4_payload.m`) | Per-elevation thermal link budget and physical impairment profile — HPA back-off, oscillator phase noise, residual CFO per payload, feeder-link penalty vector. |
| **5** | `phase5/phase5_latency.m` | End-to-end latency with the feeder hop — propagation, HARQ RTT, CDF, transparent-vs-regenerative crossover at ≈ 43° elevation. |
| **6** | `phase6_v3.m` (replaces `phase6/phase6_throughput.m`) | PDSCH throughput sweep across MCS and numerology (15 / 30 / 60 kHz SCS, FR1). |
| **6b** | `phase6b/phase6b_comparison.m` | Throughput comparison plots — transition region and operating-point bars. |
| **7** | `phase7_v3.m` (replaces `phase7/phase7_reliability.m`) | Independently simulated BLER for both payloads, real IR-HARQ with RV sequence [0 2 3 1], 95 % CI bands, NTN-TDL-C and NTN-TDL-D. The 1.48 dB headline is measured here. |
| **7c** | `phase7c/` | BLER CI smoothing pass used for the camera-ready figures. |
| **77** | `phase77/` | Early BLER-vs-SNR exploratory figure. |

### Top-level shared helpers

- `helpers/applyImpairments.m` — transmit-side HPA (Rapp), oscillator phase noise, residual CFO injection (used by phases 6 and 7).
- `helpers/firstCrossing.m` — log-interpolated 10 % BLER crossing used by all BLER-based phases.

---

## Requirements

- **MATLAB R2024a** (or newer)
- **5G Toolbox**
- **Communications Toolbox**
- No other dependencies.

The simulation has been run on MATLAB R2024a; earlier versions may work but are untested.

---

## How to reproduce the results

Open MATLAB in the repository root. Run the phases in order:

```matlab
% Phase 1 — constellation and link geometry
cd phase1_v2 ; phase1_scenario ; cd ..

% Phase 2 — NTN-TDL channel model preview
cd phase2 ; phase2_channel ; cd ..

% Phase 3 — PDSCH waveform generation
cd phase3 ; phase3_waveform ; cd ..

% Phase 4 — link budget and physical impairment profile  (v3 drop-in)
phase4_v3

% Phase 5 — end-to-end latency with feeder hop
cd phase5 ; phase5_latency ; cd ..

% Phase 6 — throughput sweep  (v3 drop-in)
phase6_v3

% Phase 7 — BLER and IR-HARQ  (v3 drop-in — the headline run)
phase7_v3
```

Each phase writes its results into its own `results/` folder (`*_results.mat` plus `.png` figures). Phase 7 is the longest — expect several minutes for the baseline, longer for the camera-ready `nSlots = 200` run described in `docs/CHANGELOG_v3.md`.

---

## Key simulation parameters

| Parameter | Value |
|---|---|
| Constellation | Walker Delta 72 / 6 / 1 |
| Altitude / inclination | 600 km / 53° |
| Carrier / bandwidth | 2.0 GHz (S-band) / 10 MHz FR1 |
| Ground infrastructure | 8 gateways · 16 UEs over Ghana |
| Primary MCS | 16QAM, R = 490/1024 ≈ 0.48 |
| MCS sweep | QPSK R = 0.12, 0.44 · 16QAM R = 0.33, 0.48 · 64QAM R = 0.55 |
| Numerology (SCS) | 15, 30, 60 kHz (FR1) |
| Channel models | NTN-TDL-C (suburban), NTN-TDL-D (rural) |
| SNR grid | −4 to 16 dB, 0.5–1 dB step |
| Blocks per SNR point | 240 = 40 slots × 6 seeds |
| HARQ | IR-HARQ, RV sequence [0, 2, 3, 1] |
| Residual CFO | ±0.1 ppm (~200 Hz @ 2 GHz), TS 38.101-5 compliant |
| HPA model | Rapp SSPA, smoothness p = 3, IBO = 4 dB |

---

## Citation

If you use this code or build on these results, please cite the paper:

```bibtex
@inproceedings{Lawerteh2026ICAST,
  author    = {Lawerteh Isaiah Amatey and Davies Kojo Egyir and Kelvin Asante Obeng and
               Clement Heanampong and James Dzisi Gadze},
  title     = {Performance Analysis of 5G NR in LEO Non-Terrestrial Networks:
               A Physics-Based Comparative Study of Transparent and Regenerative
               Payload Architectures},
  booktitle = {Proc. 10th IEEE International Conference on Adaptive Science and Technology (ICAST)},
  year      = {2026},
  address   = {Accra, Ghana},
  note      = {Paper ID 110}
}
```

A `CITATION.cff` file is also included so GitHub can render a "Cite this repository" button.

---

## License

MIT — see [`LICENSE`](LICENSE). You are free to use, modify and redistribute this code with attribution.

---

## Changelog and known pitfalls

- `docs/CHANGELOG_v3.md` — what the v3 drop-in files fix relative to the earlier Phase 4/6/7 scripts, and the reviewer comments they address.
- `docs/CHANGELOG_phase4_fix1.md` — follow-up fix for the `nrTimingEstimate` dimension bug when the TDL defaults to 2 Rx antennas.
- `docs/Simulation output command window.txt` — a representative MATLAB console trace from a Phase 7 run.

---

## Contact

For questions about the code, reproducibility, or extensions (K-band feeder links, URLLC-grade reliability, shadowed propagation): [isaiahanim20@gmail.com](mailto:isaiahanim20@gmail.com).
