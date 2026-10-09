// Stars of one or two galaxies on the GPU. Same physics as the CPU code:
//  - start(): StarSampler.sample() (identical hash, populations and velocity table)
//  - process(): fixed steps (drift–kick–drift) in the potentials of GalaxyPotential, around
//    galaxy centres that the CPU passes in for the middle of every step.
// Particle velocity is kept in CUSTOM.xyz, the host galaxy in CUSTOM.w.
shader_type particles;

const int MAX_STEPS = 24;

uniform int n_first = 100000;          // particles [0, n_first) belong to galaxy 0
uniform float pot[32];                 // 16 per galaxy, see GalaxyPotential.to_uniforms()
uniform mat3 basis[2];                 // disk frame -> world
uniform float vtab[64];                // 32 circular speeds per galaxy, r = 0 .. vtab_rmax
uniform float vtab_rmax[2];
uniform float f_bulge[2];
uniform float f_gas[2];
uniform float r_max[2];
uniform float a_bulge[2];
uniform float r_disk[2];
uniform float r_gas[2];
uniform float spin[2];
uniform vec3 start_center[2];
uniform vec3 start_vel[2];
uniform vec3 centers[48];              // per step k: galaxy 0 at 2k, galaxy 1 at 2k+1
uniform int steps = 0;                 // steps to do this frame (0 = paused)
uniform float dt = 0.05;

uniform vec4 color_core0 : source_color = vec4(1.0, 0.84, 0.6, 1.0);
uniform vec4 color_edge0 : source_color = vec4(0.55, 0.7, 1.0, 1.0);
uniform vec4 color_core1 : source_color = vec4(1.0, 0.8, 0.6, 1.0);
uniform vec4 color_edge1 : source_color = vec4(0.62, 0.66, 1.0, 1.0);
uniform vec4 color_gas : source_color = vec4(0.45, 0.6, 1.0, 1.0);
uniform vec4 color_hii : source_color = vec4(1.0, 0.35, 0.55, 1.0);
uniform float brightness = 0.22;

const float BH_SOFT = 0.01;

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float vtab_at(int g, float r) {
	float f = clamp(r / vtab_rmax[g] * 31.0, 0.0, 30.999);
	int i = int(f);
	return mix(vtab[g * 32 + i], vtab[g * 32 + i + 1], f - float(i));
}

vec3 mn_accel(vec3 p, float m, float a, float b) {
	if (m <= 0.0) return vec3(0.0);
	float s = sqrt(p.y * p.y + b * b);
	float d2 = p.x * p.x + p.z * p.z + (a + s) * (a + s);
	float d3 = d2 * sqrt(d2);
	return vec3(-m * p.x / d3, -m * p.y * (a + s) / (s * d3), -m * p.z / d3);
}

// GalaxyPotential.accel_local(), parameters at pot[o .. o + 15].
vec3 accel_local(int o, vec3 p) {
	vec3 a = vec3(0.0);
	float r2 = dot(p, p);
	float r = sqrt(r2);
	float m_bh = pot[o];
	if (m_bh > 0.0) {
		float s2 = r2 + BH_SOFT * BH_SOFT;
		a -= p * (m_bh / (s2 * sqrt(s2)));
	}
	float m_b = pot[o + 1];
	float a_b = pot[o + 2];
	if (m_b > 0.0 && r > 1e-6) a -= p * (m_b / (r * (r + a_b) * (r + a_b)));
	a += mn_accel(p, pot[o + 3], pot[o + 4], pot[o + 5]);
	a += mn_accel(p, pot[o + 6], pot[o + 7], pot[o + 8]);
	float vh = pot[o + 9];
	if (vh > 0.0) {
		float rc = pot[o + 10];
		float rt = pot[o + 11];
		if (r < rt) a -= p * (vh * vh / (r2 + rc * rc));
		else a -= p * (pot[o + 12] / (r2 * r));
	}
	return a;
}

vec3 accel(int g, vec3 rel) {
	return basis[g] * accel_local(g * 16, transpose(basis[g]) * rel);
}

void start() {
	int g = int(INDEX) < n_first ? 0 : 1;
	uint local_index = g == 0 ? INDEX : INDEX - uint(n_first) + 1000003u;
	uint s = hash_u(local_index * 747796405u + 2891336453u);
	float u[5];
	for (int i = 0; i < 5; i++) {
		u[i] = float(s) / 4294967295.0;
		s = hash_u(s);
	}
	int kind = 1;  // 0 bulge, 1 disk, 2 gas
	if (u[0] < f_bulge[g]) kind = 0;
	else if (u[0] < f_bulge[g] + f_gas[g]) kind = 2;
	vec3 pos;
	vec3 vel;
	float frac;   // 0 centre .. 1 edge (colour)
	if (kind == 0) {
		float a = a_bulge[g];
		float rmax = 4.0 * a;
		float umax = pow(rmax / (rmax + a), 2.0);
		float q = sqrt(u[1] * umax);
		float r = a * q / (1.0 - q);
		float ct = 2.0 * u[2] - 1.0;
		float st = sqrt(max(0.0, 1.0 - ct * ct));
		float ph = 6.28318530718 * u[3];
		vec3 n = vec3(st * cos(ph), ct, st * sin(ph));
		pos = n * r;
		vec3 e1 = normalize(cross(n, abs(ct) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 e2 = cross(n, e1);
		float psi = 6.28318530718 * u[4];
		vel = (e1 * cos(psi) + e2 * sin(psi)) * vtab_at(g, r);
		frac = 0.0;
	} else {
		float sc = kind == 1 ? r_disk[g] : r_gas[g];
		float rmax = r_max[g];
		float rr = -sc * log(1.0 - u[1] * (1.0 - exp(-rmax / sc)));
		float th = 6.28318530718 * u[2];
		float zh = sc * (kind == 1 ? 0.06 : 0.025);
		float h = (2.0 * u[3] - 1.0) * zh;
		float disp = 1.0 + 0.1 * (u[4] - 0.5);
		pos = vec3(rr * cos(th), h, rr * sin(th));
		vel = vec3(-sin(th), 0.0, cos(th)) * (vtab_at(g, rr) * disp * spin[g]);
		frac = clamp(rr / rmax, 0.0, 1.0);
	}
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = start_center[g] + basis[g] * pos;
	VELOCITY = vec3(0.0);
	CUSTOM = vec4(start_vel[g] + basis[g] * vel, float(g));

	// Looks only (extra random numbers, not used by the physics).
	float v1 = float(s) / 4294967295.0;
	s = hash_u(s);
	float v2 = float(s) / 4294967295.0;
	vec4 core = g == 0 ? color_core0 : color_core1;
	vec4 edge = g == 0 ? color_edge0 : color_edge1;
	vec3 c = mix(core.rgb, edge.rgb, sqrt(frac));
	float size = 0.6 + 0.8 * v1;
	float glow = brightness * (0.6 + 0.8 * v2);
	if (kind == 0) {
		c = core.rgb;
		glow *= 1.3;
	} else if (kind == 2) {
		c = v1 < 0.12 ? color_hii.rgb : color_gas.rgb;   // star-forming knots in the gas
		size *= v1 < 0.12 ? 1.8 : 2.4;
		glow *= v1 < 0.12 ? 1.4 : 0.35;
	}
	COLOR = vec4(c * glow, 1.0);
	TRANSFORM[0].x = size;
	TRANSFORM[1].y = size;
	TRANSFORM[2].z = size;
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	vec3 v = CUSTOM.xyz;
	for (int k = 0; k < MAX_STEPS; k++) {
		if (k >= steps) break;
		p += v * (0.5 * dt);
		v += (accel(0, p - centers[2 * k]) + accel(1, p - centers[2 * k + 1])) * dt;
		p += v * (0.5 * dt);
	}
	TRANSFORM[3].xyz = p;
	CUSTOM.xyz = v;
	VELOCITY = vec3(0.0);
}
