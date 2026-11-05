function [slantRange_m, propDelay_s] = computeSlantRange(elevAngle_deg, altitude_m, R_earth_m, c)
%COMPUTESLANTRANGE Compute slant range and propagation delay for a given elevation angle.
%
%   Uses the standard spherical Earth geometry formula from 3GPP TR 38.821 Sec 6.1.2:
%
%       d = sqrt( (h + Re)^2 - (Re*cos(el))^2 ) - Re*sin(el)
%
%   where:
%       h   = satellite altitude [m]
%       Re  = Earth radius [m]
%       el  = elevation angle [deg]
%       d   = slant range [m]
%
%   Inputs:
%       elevAngle_deg  - Elevation angle(s) in degrees (scalar or vector)
%       altitude_m     - Satellite altitude in meters
%       R_earth_m      - Earth radius in meters
%       c              - Speed of light in m/s
%
%   Outputs:
%       slantRange_m   - Slant range in meters (same size as elevAngle_deg)
%       propDelay_s    - One-way propagation delay in seconds

    el_rad = deg2rad(elevAngle_deg);
    
    slantRange_m = sqrt((altitude_m + R_earth_m).^2 - (R_earth_m .* cos(el_rad)).^2) ...
                   - R_earth_m .* sin(el_rad);
    
    propDelay_s = slantRange_m ./ c;
end
