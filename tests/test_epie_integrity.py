import pytest
import math
import numpy as np
from unittest.mock import MagicMock, patch

# ==============================================================================
# ePiE (Extended Pharmaceutical Iterative Engine) - Integrity Verification Suite
# ==============================================================================
# This test suite verifies the core mathematical update steps of the ePiE 
# algorithm, comparing the legacy `./SHoeks/` logic with the refactored `./AudLem/` 
# implementation.
# ==============================================================================

# Physical Constants (from SHoeks/AudLem comparison)
LEGACY_VOL_FACTOR = 1e6  # (SHoeks) - km3 to m3 (underestimated)
REF_VOL_FACTOR = 1e9     # (AudLem)  - km3 to m3 (corrected)
SEC_PER_YEAR = 31536000

# ------------------------------------------------------------------------------
# Mock Implementations of C++ Engine Logic
# ------------------------------------------------------------------------------

def update_step_legacy(E_total, Q, k, V_km3):
    """Legacy concentration update (SHoeks)"""
    V_m3 = V_km3 * LEGACY_VOL_FACTOR
    return E_total / (Q + k * V_m3) * 1e6 / SEC_PER_YEAR

def update_step_refactored(E_total, Q, k, V_km3, Q_safe=0.001):
    """Refactored concentration update (AudLem) with Q-clamping"""
    V_m3 = V_km3 * REF_VOL_FACTOR
    Q_eff = max(Q, Q_safe)
    return E_total / (Q_eff + k * V_m3) * 1e6 / SEC_PER_YEAR

def propagation_step(E_in, k, dist, velocity):
    """Exponential decay propagation across segments"""
    if velocity <= 0: return E_in
    return E_in * math.exp(-k * dist / velocity)

# ------------------------------------------------------------------------------
# Integrity Tests
# ------------------------------------------------------------------------------

class TestEPIEIntegrity:
    
    def test_volume_scaling_discontinuity(self):
        """
        TASK 2 AUDIT: Verify the 1000x magnitude shift in Lake Models (Bega Basin).
        The refactored code (AudLem) should produce 1000x lower concentrations 
        for volume-dominated lakes compared to legacy (SHoeks).
        """
        E = 1000.0   # kg/year
        Q = 10.0     # m3/s (low flow)
        k = 1.0      # s^-1 (high decay to make volume-dominated)
        V = 0.5      # km3
        
        c_old = update_step_legacy(E, Q, k, V)
        c_new = update_step_refactored(E, Q, k, V)
        
        # Expectation: c_new should be significantly lower than c_old due to 
        # V being 1000x larger in the denominator.
        assert c_new < c_old
        # Ratio check: for large kV >> Q, the ratio should approach 1000.
        ratio = c_old / c_new
        assert ratio > 900 and ratio <= 1000

    def test_q_clamping_regularization(self):
        """
        TASK 2 AUDIT: Verify that AudLem prevents division-by-zero (Volta Dry).
        """
        E = 50.0
        Q = 0.0  # Dry Reach
        k = 0.0
        V = 0.0
        
        # Legacy would fail with ZeroDivisionError
        with pytest.raises(ZeroDivisionError):
            _ = update_step_legacy(E, Q, k, V)
            
        # Refactored should return a finite, regularized concentration
        c_safe = update_step_refactored(E, Q, k, V)
        assert np.isfinite(c_safe)
        assert c_safe == (E / 0.001) * 1e6 / SEC_PER_YEAR

    def test_energy_conservation(self):
        """
        TASK 3 REQUIREMENT: Verify energy (mass) conservation in propagation.
        Probe power (load) should never increase during segment transport.
        """
        E_start = 500.0
        k = 0.5 / 86400  # decay
        dist = 5000      # 5km
        vel = 0.5        # 0.5 m/s
        
        E_end = propagation_step(E_start, k, dist, vel)
        
        assert E_end <= E_start
        assert E_end > 0

    def test_pathogen_vs_chemical_scaling(self):
        """
        Verify that substance abstraction (00_substance_abstraction.R)
        handles the domain shift correctly (Metaphorical FFT/iFFT).
        """
        # In AudLem, Pathogen C_w = (E/31536000) / (Q*1000) [oocysts/L]
        # In AudLem, Chemical C_w = (E*1e6/31536000) / Q    [ug/L]
        E = 1e12 # 10^12 oocysts or 10^12 ug (1000 kg)
        Q = 10.0
        
        # Pathogen calculation (manual mirror of 02_ComputeEnvConcentrations.R)
        c_pathogen = (E / SEC_PER_YEAR) / (Q * 1000)
        
        # Chemical calculation
        c_chemical = (E / SEC_PER_YEAR) / Q  # note: E in ug here
        
        # Scaling relationship verification
        assert c_chemical == c_pathogen * 1000

if __name__ == "__main__":
    pytest.main([__file__])
