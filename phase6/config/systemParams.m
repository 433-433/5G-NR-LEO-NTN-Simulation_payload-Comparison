function params = systemParams()
%SYSTEMPARAMS Centralized parameter configuration for 5G NR LEO NTN project.
%   All parameters are traceable to 3GPP specifications.
%   This file is called by every phase script to ensure consistency.
%
%   Usage:  params = systemParams();
%
%   References:
%       3GPP TR 38.811 v17.0.0 - Study on NR to support NTN
%       3GPP TR 38.821 v17.2.0 - Solutions for NR NTN
%       3GPP TS 38.101-5       - NR UE radio transmission/reception for NTN
%       3GPP TS 38.211         - Physical channels and modulation

%% =====================================================================
%  PHYSICAL CONSTANTS
%  =====================================================================
params.c           = physconst('lightspeed');    % Speed of light [m/s]
params.k_boltz     = physconst('Boltzmann');     % Boltzmann constant [J/K]
params.R_earth     = 6371e3;                     % Mean Earth radius [m]

%% =====================================================================
%  ORBITAL PARAMETERS  (TR 38.821 Table 6.1.1-1, Scenario LEO-600)
%  =====================================================================
params.sat.altitude       = 600e3;               % Orbital altitude [m]
params.sat.inclination    = 53;                  % Orbital inclination [deg]
params.sat.eccentricity   = 0;                   % Circular orbit
params.sat.numPlanes      = 6;                   % Number of orbital planes
params.sat.satsPerPlane   = 12;                  % Satellites per plane
params.sat.numSats        = params.sat.numPlanes * params.sat.satsPerPlane;  % Total = 72
params.sat.semiMajorAxis  = params.R_earth + params.sat.altitude;  % [m]

% Walker Delta constellation phasing
params.sat.walkerF        = 1;                   % Walker phasing factor

%% =====================================================================
%  RF / LINK PARAMETERS  (TR 38.821 Table 6.1.1-1, S-band scenario)
%  =====================================================================
params.rf.carrierFrequency  = 2e9;               % Carrier frequency [Hz] (S-band)
params.rf.wavelength        = params.c / params.rf.carrierFrequency;  % [m]
params.rf.channelBandwidth  = 10e6;              % Channel bandwidth [Hz]
params.rf.sampleRate        = 15.36e6;           % Sample rate for 10 MHz BW, 15 kHz SCS

% Satellite antenna (TR 38.821 Table 6.1.1-1)
params.rf.satAntennaGain_dBi   = 30;            % Satellite antenna gain [dBi]
params.rf.satNoiseFigure_dB    = 1.5;           % Satellite receiver noise figure [dB]
params.rf.satTxPower_dBm       = 43;            % Sat Tx power per beam [dBm] (20W typical LEO)

% UE parameters (TS 38.101-5)
params.rf.ueAntennaGain_dBi    = 0;             % Omnidirectional UE antenna [dBi]
params.rf.ueNoiseFigure_dB     = 7;             % UE noise figure [dB]
params.rf.ueTxPower_dBm        = 23;            % UE max transmit power [dBm] (Class 3)

% Gateway parameters
params.rf.gwAntennaGain_dBi    = 43;            % Parabolic dish antenna [dBi]
params.rf.gwNoiseFigure_dB     = 1.2;           % Gateway receiver noise figure [dB]

% Atmospheric / miscellaneous losses
params.rf.atmosphericLoss_dB   = 0.5;           % Clear sky atmospheric loss [dB]
params.rf.scintillationLoss_dB = 0.5;           % Tropospheric scintillation [dB]
params.rf.polarizationLoss_dB  = 0.3;           % Polarization mismatch [dB]
params.rf.bodyLoss_dB          = 3;             % Body loss for handheld UE [dB]

%% =====================================================================
%  UE MOBILITY  (TR 38.811 Table 6.7.1-1)
%  =====================================================================
params.ue.speed_kmh       = 3;                   % Pedestrian speed [km/h]
params.ue.speed_ms        = params.ue.speed_kmh * 1000 / 3600;  % [m/s]
params.ue.minElevation    = 10;                  % Minimum service elevation angle [deg]

%% =====================================================================
%  5G NR NUMEROLOGY  (TS 38.211 Table 4.2-1)
%  =====================================================================
params.nr.scsValues       = [15 30 60 120 240];  % All standard SCS [kHz]
params.nr.scsNTN          = [15 30];             % Primary NTN SCS values [kHz]

% Resource blocks per SCS for 10 MHz bandwidth (TS 38.101-1 Table 5.3.2-1)
params.nr.rbCount_10MHz   = [52 24 11 0 0];     % RBs for [15 30 60 120 240] kHz
params.nr.rbCount_20MHz   = [106 51 24 11 0];   % RBs for 20 MHz BW

% Modulation orders available
params.nr.modulationSchemes = {'QPSK', '16QAM', '64QAM', '256QAM'};

%% =====================================================================
%  CHANNEL MODEL  (TR 38.811 Section 6.9.2)
%  =====================================================================
params.channel.seed           = 73;              % Random seed for reproducibility
params.channel.randomStream   = "mt19937ar with seed";

% Delay spread per environment (TR 38.811 Table 6.9.2-1)
params.channel.delaySpread.denseUrban = 200e-9;  % NTN-TDL-A
params.channel.delaySpread.urban      = 75e-9;   % NTN-TDL-B
params.channel.delaySpread.suburban   = 50e-9;   % NTN-TDL-C
params.channel.delaySpread.rural      = 20e-9;   % NTN-TDL-D

%% =====================================================================
%  SIMULATION CONTROL
%  =====================================================================
params.sim.startTime      = datetime(2024,6,15,0,0,0);   % Scenario start (midnight UTC)
params.sim.timeStep       = 30;                  % Time step for tracking [s]
params.sim.rngSeed        = 42;                  % Master RNG seed

% Orbital period for 600 km LEO [s]
mu = 3.986004418e14;                             % Earth gravitational parameter
params.sim.orbitalPeriod  = 2*pi*sqrt(params.sat.semiMajorAxis^3 / mu);
% Duration: 24 hours (full Earth rotation ensures all orbital planes cross Ghana)
params.sim.duration       = hours(24);

%% =====================================================================
%  GROUND STATION LOCATIONS  (Ghana)
%  8 Gateways across all regions of Ghana
%  =====================================================================
params.gw.names = ["GW_Accra",    "GW_Kumasi",   "GW_Tamale",    "GW_Bolgatanga", ...
                    "GW_Takoradi", "GW_Sunyani",  "GW_Ho",        "GW_WA"];
params.gw.lat   = [5.6037,  6.6918,  9.4114,  10.7911, ...
                    4.9333,  7.3400,  6.6000,  10.0601];
params.gw.lon   = [-0.1870, -1.6169, -0.8350, -0.8480, ...
                    -1.7167, -2.3286, 0.4700,  -2.5099];
params.gw.count = length(params.gw.names);

%% =====================================================================
%  UE LOCATIONS (16 UEs — 2 near each gateway)
%  Each UE is placed 5-20 km from its parent gateway
%  =====================================================================
params.ue.names = [ ...
    "UE_Accra1",    "UE_Accra2", ...       % Near GW_Accra
    "UE_Kumasi1",   "UE_Kumasi2", ...      % Near GW_Kumasi
    "UE_Tamale1",   "UE_Tamale2", ...      % Near GW_Tamale
    "UE_Bolga1",    "UE_Bolga2", ...       % Near GW_Bolgatanga
    "UE_Takoradi1", "UE_Takoradi2", ...    % Near GW_Takoradi
    "UE_Sunyani1",  "UE_Sunyani2", ...     % Near GW_Sunyani
    "UE_Ho1",       "UE_Ho2", ...          % Near GW_Ho
    "UE_WA1",       "UE_WA2"  ...          % Near GW_WA
];
% ~0.05-0.15 deg offset ≈ 5-17 km
params.ue.lat = [ ...
    5.65,  5.55, ...     % Accra
    6.75,  6.63, ...     % Kumasi
    9.45,  9.35, ...     % Tamale
    10.85, 10.72, ...    % Bolgatanga
    4.98,  4.88, ...     % Takoradi
    7.40,  7.28, ...     % Sunyani
    6.65,  6.55, ...     % Ho
    10.10, 10.00  ...    % WA
];
params.ue.lon = [ ...
    -0.13, -0.25, ...   % Accra
    -1.55, -1.68, ...   % Kumasi
    -0.78, -0.90, ...   % Tamale
    -0.80, -0.90, ...   % Bolgatanga
    -1.65, -1.78, ...   % Takoradi
    -2.28, -2.40, ...   % Sunyani
     0.52,  0.42, ...   % Ho
    -2.45, -2.57  ...   % WA
];
params.ue.count = length(params.ue.names);

%% =====================================================================
%  OUTPUT CONFIGURATION
%  =====================================================================
params.outputDir = fullfile(pwd, 'results');
if ~exist(params.outputDir, 'dir')
    mkdir(params.outputDir);
end

end
