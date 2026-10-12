// Black sky with procedural stars (3D cell hashing on the sky sphere) and a faint Milky Way
// band, for the solar-system scene (no horizon: we are in space).
shader_type sky;

uniform float star_scale = 260.0;
uniform float star_brightness = 0.45;
uniform vec3 galactic_pole = vec3(-0.45, 0.62, 0.64);   // set to the real pole by SolarView
uniform float band = 1.0;                                // Milky Way band (0 when we look at it from outside)

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i), n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0)), n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1)), n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1)), n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
	           mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float density) {
	vec3 g = dir * scale;
	vec3 id = floor(g);
	vec3 side = step(0.5, fract(g)) * 2.0 - 1.0;
	float acc = 0.0;
	for (int z = 0; z <= 1; z++)
	for (int y = 0; y <= 1; y++)
	for (int x = 0; x <= 1; x++) {
		vec3 cid = id + vec3(float(x), float(y), float(z)) * side;
		float h = hash13(cid);
		if (h > density) continue;
		vec3 sp = normalize(cid + hash33(cid));
		float d = length(dir - sp) * scale;
		float mag = pow(hash13(cid + 5.7), 4.0);
		acc += mag * (1.0 - smoothstep(0.0, 0.08 + 0.12 * mag, d));
	}
	return acc;
}

void sky() {
	vec3 dir = EYEDIR;
	float s = stars(dir, star_scale, 0.08) + stars(dir, star_scale * 0.45, 0.05) * 1.5;
	float b = band * exp(-pow(dot(dir, normalize(galactic_pole)) / 0.22, 2.0));
	float mw = b * fbm(dir * 6.0) * (0.6 + 0.4 * fbm(dir * 18.0 + 3.0));
	COLOR = vec3(0.002, 0.003, 0.008) + vec3(0.75, 0.8, 1.0) * s * 2.2 * star_brightness * (1.0 + b)
		+ vec3(0.07, 0.065, 0.08) * mw;
}
