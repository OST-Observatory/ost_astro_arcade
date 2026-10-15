#[compute]
#version 450
// Test stars of a galaxy collision on the GPU, for the feature detector: the same drift–kick–
// drift steps in the same potentials as EncounterModel.run_stars() and galaxy_stars.gdshader,
// one invocation per star. Every `every` steps a snapshot: the positions of a subsample (for
// tails and bridges) and, for all stars, counts in each galaxy's disk plane by direction and
// radius (for rings – with tens of thousands of stars faint rings stand out).

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

// p[0] stars, p[1] steps, p[2] dt, p[3] steps per snapshot,
// p[4..35] potentials (16 per galaxy, GalaxyPotential.to_uniforms()),
// p[36..53] disk frames (3 columns per galaxy),
// p[54] stars per galaxy, p[55] subsample per galaxy, p[56..57] half thickness counted,
// p[58..59] outer radius counted (per galaxy)
layout(set = 0, binding = 0, std430) restrict readonly buffer Params { float p[]; } prm;
layout(set = 0, binding = 1, std430) restrict readonly buffer Centers { vec4 c[]; } ctr;   // step k: galaxy 0 at 2k, 1 at 2k+1
layout(set = 0, binding = 2, std430) restrict readonly buffer Init { vec4 s[]; } init;     // star i: position at 2i, velocity at 2i+1
layout(set = 0, binding = 3, std430) restrict writeonly buffer Snaps { vec4 o[]; } snaps;  // snapshot j, subsample star s at j*2m+s
layout(set = 0, binding = 4, std430) restrict buffer Hist { uint h[]; } hist;               // ((j*2+g)*DIRS+d)*BINS+b
layout(set = 0, binding = 5, std430) restrict readonly buffer SnapCenters { vec4 c[]; } sc;  // snapshot j: galaxy g at 2j+g

const int DIRS = 12;
const int BINS = 160;

const float BH_SOFT = 0.01;

vec3 mn_accel(vec3 q, float m, float a, float b) {
	if (m <= 0.0) return vec3(0.0);
	float s = sqrt(q.y * q.y + b * b);
	float d2 = q.x * q.x + q.z * q.z + (a + s) * (a + s);
	float d3 = d2 * sqrt(d2);
	return vec3(-m * q.x / d3, -m * q.y * (a + s) / (s * d3), -m * q.z / d3);
}

vec3 accel_local(int o, vec3 q) {
	vec3 a = vec3(0.0);
	float r2 = dot(q, q);
	float r = sqrt(r2);
	float m_bh = prm.p[o];
	if (m_bh > 0.0) {
		float s2 = r2 + BH_SOFT * BH_SOFT;
		a -= q * (m_bh / (s2 * sqrt(s2)));
	}
	float m_b = prm.p[o + 1];
	float a_b = prm.p[o + 2];
	if (m_b > 0.0 && r > 1e-6) a -= q * (m_b / (r * (r + a_b) * (r + a_b)));
	a += mn_accel(q, prm.p[o + 3], prm.p[o + 4], prm.p[o + 5]);
	a += mn_accel(q, prm.p[o + 6], prm.p[o + 7], prm.p[o + 8]);
	float vh = prm.p[o + 9];
	if (vh > 0.0) {
		float rc = prm.p[o + 10];
		float rt = prm.p[o + 11];
		if (r < rt) a -= q * (vh * vh / (r2 + rc * rc));
		else a -= q * (prm.p[o + 12] / (r2 * r));
	}
	return a;
}

mat3 basis(int g) {
	int o = 36 + g * 9;
	return mat3(vec3(prm.p[o], prm.p[o + 1], prm.p[o + 2]), vec3(prm.p[o + 3], prm.p[o + 4], prm.p[o + 5]),
		vec3(prm.p[o + 6], prm.p[o + 7], prm.p[o + 8]));
}

vec3 accel(int g, mat3 b, vec3 rel) {
	return b * accel_local(4 + g * 16, transpose(b) * rel);
}

void record(uint j, vec3 x, uint g, uint local, uint m, mat3 bg) {
	if (local < m) {
		snaps.o[j * 2u * m + g * m + local] = vec4(x, 1.0);
	}
	vec3 q = transpose(bg) * (x - sc.c[2u * j + g].xyz);
	if (abs(q.y) > prm.p[56 + g]) return;
	float rr = length(q.xz);
	float rmax = prm.p[58 + g];
	if (rr >= rmax) return;
	int d = int(mod(atan(q.z, q.x), 6.2831853) / 6.2831853 * float(DIRS)) % DIRS;
	int b = int(rr / rmax * float(BINS));
	atomicAdd(hist.h[((int(j) * 2 + int(g)) * DIRS + d) * BINS + b], 1u);
}

void main() {
	uint i = gl_GlobalInvocationID.x;
	uint n = uint(prm.p[0]);
	if (i >= n) return;
	int steps = int(prm.p[1]);
	float dt = prm.p[2];
	int every = int(prm.p[3]);
	mat3 b0 = basis(0);
	mat3 b1 = basis(1);
	vec3 x = init.s[2 * i].xyz;
	vec3 v = init.s[2 * i + 1].xyz;
	uint per = uint(prm.p[54]);
	uint m = uint(prm.p[55]);
	uint g = i < per ? 0u : 1u;
	uint local = i - g * per;
	mat3 bg = g == 0u ? b0 : b1;
	record(0u, x, g, local, m, bg);
	uint j = 1u;
	for (int k = 0; k < steps; k++) {
		x += v * (0.5 * dt);
		v += (accel(0, b0, x - ctr.c[2 * k].xyz) + accel(1, b1, x - ctr.c[2 * k + 1].xyz)) * dt;
		x += v * (0.5 * dt);
		if ((k + 1) % every == 0) {
			record(j, x, g, local, m, bg);
			j++;
		}
	}
}
