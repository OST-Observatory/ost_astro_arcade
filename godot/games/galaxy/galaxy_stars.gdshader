// Galaxy encounter on the GPU: every particle is a massless test star in the softened
// potential of the two galaxy cores (same physics as GalaxyModel on the CPU). The cores'
// track comes from the CPU: positions at the start and end of the frame, interpolated per
// substep. Velocity lives in CUSTOM.xyz, CUSTOM.w is the host galaxy (0 or 1).
shader_type particles;

uniform int n_first = 100000;          // particles [0, n_first) belong to galaxy 0
uniform float G = 1.0;
uniform float softening = 0.5;
uniform int substeps = 6;
uniform float step_dt = 0.0;           // simulated time this frame (0 = paused)

uniform vec3 core_from[2];
uniform vec3 core_to[2];
uniform vec3 core_vel[2];              // at t = 0, for the initial disks
uniform float core_mass[2];
uniform float disk_scale[2];
uniform mat3 disk_basis[2];            // local disk plane xz -> world
uniform float disk_spin[2];            // +1 or -1
uniform float disk_rmin = 1.0;
uniform float disk_rmax = 7.0;
uniform float disk_len = 2.2;          // exponential scale length
uniform float bulge_fraction = 0.12;

uniform vec4 color_core0 : source_color = vec4(1.0, 0.82, 0.58, 1.0);
uniform vec4 color_edge0 : source_color = vec4(0.5, 0.68, 1.0, 1.0);
uniform vec4 color_core1 : source_color = vec4(1.0, 0.76, 0.52, 1.0);
uniform vec4 color_edge1 : source_color = vec4(0.62, 0.62, 1.0, 1.0);
uniform vec4 color_hii : source_color = vec4(1.0, 0.35, 0.55, 1.0);
uniform float brightness = 0.22;

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float rnd(inout uint s) {
	s = hash_u(s);
	return float(s) / 4294967295.0;
}

vec3 accel(vec3 p, vec3 c0, vec3 c1) {
	vec3 d0 = c0 - p;
	vec3 d1 = c1 - p;
	float e2 = softening * softening;
	float r0 = dot(d0, d0) + e2;
	float r1 = dot(d1, d1) + e2;
	return G * (core_mass[0] * d0 * inversesqrt(r0 * r0 * r0) + core_mass[1] * d1 * inversesqrt(r1 * r1 * r1));
}

void start() {
	uint seed = hash_u(INDEX * 747796405u + 2891336453u);
	int g = int(INDEX) < n_first ? 0 : 1;
	float s = disk_scale[g];
	float rmin = disk_rmin * s;
	float rmax = disk_rmax * s;
	float len = disk_len * s;
	bool bulge = rnd(seed) < bulge_fraction;
	float r;
	float h;
	if (bulge) {
		float b = rnd(seed);
		r = (0.15 + 1.1 * b * b) * s;
		h = (rnd(seed) - 0.5) * 0.9 * r;
	} else {
		float u = rnd(seed);
		r = rmin - len * log(1.0 - u * (1.0 - exp(-(rmax - rmin) / len)));
		h = (rnd(seed) - 0.5) * 0.12 * (1.0 + r * 0.05);
	}
	float th = TAU * rnd(seed);
	vec3 local_p = vec3(r * cos(th), h, r * sin(th));
	vec3 local_t = vec3(-sin(th), 0.0, cos(th)) * disk_spin[g];
	float e2 = softening * softening;
	float v_circ = sqrt(G * core_mass[g] * r * r / pow(r * r + e2, 1.5));

	vec3 p = core_from[g] + disk_basis[g] * local_p;
	vec3 v = core_vel[g] + disk_basis[g] * (local_t * v_circ);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = p;
	VELOCITY = vec3(0.0);
	CUSTOM = vec4(v, float(g));

	float f = clamp((r - rmin) / (rmax - rmin), 0.0, 1.0);
	vec4 c = g == 0 ? mix(color_core0, color_edge0, sqrt(f)) : mix(color_core1, color_edge1, sqrt(f));
	float size = 0.6 + 0.8 * rnd(seed);
	float glow = brightness * (0.6 + 0.8 * rnd(seed));
	if (bulge) {
		c = g == 0 ? color_core0 : color_core1;
		glow *= 1.3;
	} else if (f > 0.15 && rnd(seed) < 0.015) {
		c = color_hii;      // star-forming knots in the arms
		size *= 1.8;
		glow *= 1.6;
	}
	COLOR = vec4(c.rgb * glow, 1.0);
	TRANSFORM[0].x = size;
	TRANSFORM[1].y = size;
	TRANSFORM[2].z = size;
}

void process() {
	if (step_dt > 0.0) {
		vec3 p = TRANSFORM[3].xyz;
		vec3 v = CUSTOM.xyz;
		float dt = step_dt / float(substeps);
		for (int i = 0; i < substeps; i++) {
			float k = (float(i) + 0.5) / float(substeps);
			v += accel(p, mix(core_from[0], core_to[0], k), mix(core_from[1], core_to[1], k)) * dt;
			p += v * dt;
		}
		TRANSFORM[3].xyz = p;
		CUSTOM.xyz = v;
	}
	VELOCITY = vec3(0.0);
}
