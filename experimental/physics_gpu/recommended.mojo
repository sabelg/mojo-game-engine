"""Recommended opt-in experimental GPU response; ordinary engine API unchanged.

Position-first G04 stability implementation. Original G04a/b owners remain
available in their named modules for regression/counterexample reproduction.
Midpoint slop and integration/dissipation limits are documented in STABILITY.md.
"""
from .stable_friction import GpuStableFrictionResponse as GpuPhysicsResponse
from .stable_friction import StableReport as GpuPhysicsReport
