## Positions of the big moons relative to their planet (ecliptic J2000 axes, AU):
##   Moon     , Meeus, Astronomical Algorithms ch. 47, main terms (about 0.3 deg, 1000 km)
##   Io, Europa, Ganymede, Callisto, circular orbits in Jupiter's equator with Meeus' mean
##              motions (ch. 44, low accuracy)
##   Titan    , circular orbit in Saturn's equator
class_name Moons
extends RefCounted

const KM_PER_AU := 149597870.7
## [planet, radius of orbit (km), period (days), phase at J2000 (deg)]
const CIRCULAR := {
	"io": ["jupiter", 421700.0, 1.769137786, 163.8069],
	"europa": ["jupiter", 671034.0, 3.551181041, 358.4140],
	"ganymede": ["jupiter", 1070412.0, 7.15455296, 5.7176],
	"callisto": ["jupiter", 1882709.0, 16.6890184, 224.8092],
	"titan": ["saturn", 1221870.0, 15.945421, 0.0],
}


## Geocentric ecliptic longitude, latitude (deg) and distance (km) of the Moon.
static func moon_lbr(jd: float) -> Vector3:
	var t := (jd - 2451545.0) / 36525.0
	var lp := deg_to_rad(218.3164477 + 481267.88123421 * t)
	var d := deg_to_rad(297.8501921 + 445267.1114034 * t)
	var m := deg_to_rad(357.5291092 + 35999.0502909 * t)
	var mp := deg_to_rad(134.9633964 + 477198.8675055 * t)
	var f := deg_to_rad(93.2720950 + 483202.0175233 * t)
	var lon := rad_to_deg(lp) + 6.288774 * sin(mp) + 1.274027 * sin(2.0 * d - mp) + 0.658314 * sin(2.0 * d) \
		+ 0.213618 * sin(2.0 * mp) - 0.185116 * sin(m) - 0.114332 * sin(2.0 * f)
	var lat := 5.128122 * sin(f) + 0.280602 * sin(mp + f) + 0.277693 * sin(mp - f) + 0.173237 * sin(2.0 * d - f)
	var dist := 385000.56 - 20905.355 * cos(mp) - 3699.111 * cos(2.0 * d - mp) - 2955.968 * cos(2.0 * d) \
		- 569.925 * cos(2.0 * mp)
	return Vector3(fposmod(lon, 360.0), lat, dist)


static func moon_offset(jd: float) -> Vector3:
	var lbr := moon_lbr(jd)
	var lo := deg_to_rad(lbr.x)
	var la := deg_to_rad(lbr.y)
	return Vector3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la)) * (lbr.z / KM_PER_AU)


## Offset of a moon from its planet (AU, ecliptic axes).
static func offset(moon: String, jd: float) -> Vector3:
	if moon == "moon":
		return moon_offset(jd)
	var c: Array = CIRCULAR[moon]
	var ang := deg_to_rad(float(c[3]) + 360.0 / float(c[2]) * (jd - 2451545.0))
	var local := Vector3(cos(ang), sin(ang), 0.0) * (float(c[1]) / KM_PER_AU)
	return Rotation.equator_basis(c[0]) * local


static func planet_of(moon: String) -> String:
	return "earth" if moon == "moon" else str(CIRCULAR[moon][0])
