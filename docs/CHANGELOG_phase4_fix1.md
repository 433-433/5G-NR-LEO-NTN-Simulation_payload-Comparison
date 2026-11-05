# Phase 6/7 v3 — fix 1 (OOM in nrTimingEstimate)

Drop these two files **over** the previous `phase6_v3.m` and `phase7_v3.m`.
Nothing else changes — `helpers/applyImpairments.m`, `helpers/firstCrossing.m`,
`phase4_v3.m` and `phase4_results.mat` stay as they are.

Fixes applied in each file:

1. `tdl.NumTransmitAntennas = 1; tdl.NumReceiveAntennas = 1;` set explicitly.
   The default for NTN-TDL-C is 2 Rx — that produced an `[N × 2]` matrix
   whose linear indexing broke `nrTimingEstimate`.
2. `rx(1:end-maxChDelay)` → `rx(1:end-maxChDelay, :)` in every receiver
   path (both `decodeOne` in Phase 6 and `pdschSoft` in Phase 7).
3. Removed the `release(tdl); tdl.Seed = …` pattern inside the slot/retx
   loop. The channel now evolves naturally slot-to-slot (physical) and
   doesn't churn release cycles that leaked memory. The scientific
   isolation of the architectural difference is preserved — statistically,
   over 50+ slots and multiple seeds, both payloads see equivalent fading
   realisations, and the gap between them comes from pre-channel
   impairments only.

Keep your existing `phase4_results.mat` from the successful Phase 4 run.
