"""
Estimate outdoor seating location for a café.

Strategy (MVP): shift the café point toward the nearest street/road.
Simplified: shift toward the south-facing side of the building 
(most Copenhagen outdoor seating faces south for sun exposure).
"""
import math


def estimate_seating_point(
    cafe_lon: float,
    cafe_lat: float,
    building_polygon=None,
    offset_meters: float = 5.0,
) -> tuple[float, float]:
    """
    Return estimated seating (lon, lat).
    
    MVP: offset the café centroid ~5m to the south (most terraces face south).
    V2: find nearest street edge, or use building façade orientation.
    """
    # ~5m south offset in WGS84 degrees
    meters_per_degree_lat = 111_320.0
    lat_offset = offset_meters / meters_per_degree_lat
    return cafe_lon, cafe_lat - lat_offset  # shift south
