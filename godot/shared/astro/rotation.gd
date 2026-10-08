## Spin axes and rotation of the planets (IAU WGCCRE 2015): pole right ascension and
## declination (J2000, deg) and prime meridian W = W0 + Wd * days since J2000.
## Converted to ecliptic axes, so a planet's equator plane is known (rings, moons, textures).
class_name Rotation
extends RefCounted

const OBLIQUITY := 23.4392911   # deg, J2000
## [pole RA, pole Dec, W0, W per day]
const POLES := {
	"sun": [286.13, 63.87, 84.176, 14.1844],
	"mercury": [281.0103, 61.4155, 329.5988, 6.1385108],
	"venus": [272.76, 67.16, 160.20, -1.4813688],
	"earth": [0.0, 90.0, 190.147, 360.9856235],
	"moon": [269.9949, 66.5392, 38.3213, 13.17635815],
	"mars": [317.269202, 54.432516, 176.049863, 350.891982443297],
	"jupiter": [268.056595, 64.495303, 284.95, 870.536],
	"saturn": [40.589, 83.537, 38.90, 810.7939024],
	"uranus": [257.311, -15.175, 203.81, -501.1600928],
	"neptune": [299.36, 43.46, 249.978, 541.1397757],
	"pluto": [132.993, -6.163, 302.695, -56.3625225],
}


## Equatorial (J2000) unit vector -> ecliptic.
static func eq_to_ecl(v: Vector3) -> Vector3:
	var e := deg_to_rad(OBLIQUITY)
	return Vector3(v.x, cos(e) * v.y + sin(e) * v.z, -sin(e) * v.y + cos(e) * v.z)


## The planet's spin axis (north pole) as an ecliptic unit vector.
static func pole(body: String) -> Vector3:
	var p: Array = POLES.get(body, [0.0, 90.0, 0.0, 0.0])
	var ra := deg_to_rad(float(p[0]))
	var dec := deg_to_rad(float(p[1]))
	return eq_to_ecl(Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)))


## Basis whose z axis is the spin axis and x axis the node of the equator on the ecliptic:
## local (x, y, 0) lies in the planet's equator.
static func equator_basis(body: String) -> Basis:
	var z := pole(body)
	var x := Vector3(0, 0, 1).cross(z)
	if x.length() < 1e-6:
		x = Vector3(1, 0, 0)
	x = x.normalized()
	var y := z.cross(x)
	return Basis(x, y, z)


## Rotation angle of the prime meridian (deg).
static func spin_angle(body: String, jd: float) -> float:
	var p: Array = POLES.get(body, [0.0, 90.0, 0.0, 0.0])
	return fposmod(float(p[2]) + float(p[3]) * (jd - 2451545.0), 360.0)
