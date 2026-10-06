// Restricted three-body galaxy encounter (Toomre & Toomre style), fully on the GPU.
// Every particle is a massless test star orbiting in the softened potential of two
// moving point masses (the galaxy cores). The cores are integrated on the CPU and
// passed in as uniforms each frame. Particle velocity lives in CUSTOM.xyz,
// CUSTOM.w holds the host galaxy (0 or 1).
shader_type particles;

uniform int n_first = 150000;      // particles [0, n_first) belong to galaxy 0
uniform float G = 1.0;
uniform float softening = 0.5;
uniform float time_scale = 8.0;
uniform int substeps = 4;

uniform vec3 core_pos[2];
uniform vec3 core_vel[2];
uniform float core_mass[2];
uniform mat3 disk_basis[2];        // local disk plane xz -> world
uniform float disk_spin[2];        // +1 or -1
uniform float disk_rmin = 1.0;
uniform float disk_rmax = 7.0;
uniform float disk_scale = 2.2;    // exponential scale length

uniform vec4 color_core0 : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform vec4 color_edge0 : source_color = vec4(0.45, 0.65, 1.0, 1.0);
uniform vec4 color_core1 : source_color = vec4(1.0, 0.75, 0.55, 1.0);
uniform vec4 color_edge1 : source_color = vec4(0.75, 0.55, 1.0, 1.0);
uniform float brightness = 0.45;

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

vec3 accel(vec3 p) {
	vec3 a = vec3(0.0);
	for (int k = 0; k < 2; k++) {
		vec3 d = core_pos[k] - p;
		float r2 = dot(d, d) + softening * softening;
		a += G * core_mass[k] * d * inversesqrt(r2 * r2 * r2);
	}
	return a;
}

void start() {
	uint seed = hash_u(INDEX * 747796405u + 2891336453u);
	int g = int(INDEX) < n_first ? 0 : 1;

	// Exponential disk, truncated to [rmin, rmax].
	float u = rnd(seed);
	float r = disk_rmin - disk_scale * log(1.0 - u * (1.0 - exp(-(disk_rmax - disk_rmin) / disk_scale)));
	float th = TAU * rnd(seed);
	float h = (rnd(seed) - 0.5) * 0.15 * (1.0 + r * 0.05);
	vec3 local_p = vec3(r * cos(th), h, r * sin(th));
	vec3 local_t = vec3(-sin(th), 0.0, cos(th)) * disk_spin[g];

	float eps2 = softening * softening;
	float v_circ = sqrt(G * core_mass[g] * r * r / pow(r * r + eps2, 1.5));

	vec3 p = core_pos[g] + disk_basis[g] * local_p;
	vec3 v = core_vel[g] + disk_basis[g] * (local_t * v_circ);

	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = p;
	VELOCITY = vec3(0.0);
	CUSTOM = vec4(v, float(g));

	float f = clamp((r - disk_rmin) / (disk_rmax - disk_rmin), 0.0, 1.0);
	vec4 c = g == 0 ? mix(color_core0, color_edge0, f) : mix(color_core1, color_edge1, f);
	float twinkle = 0.6 + 0.8 * rnd(seed);
	COLOR = vec4(c.rgb * brightness * twinkle, 1.0);
	float s = 0.6 + 0.8 * rnd(seed);
	TRANSFORM[0].x = s;
	TRANSFORM[1].y = s;
	TRANSFORM[2].z = s;
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	vec3 v = CUSTOM.xyz;
	float dt = DELTA * time_scale / float(substeps);
	for (int i = 0; i < substeps; i++) {
		v += accel(p) * dt;   // symplectic (semi-implicit) Euler
		p += v * dt;
	}
	TRANSFORM[3].xyz = p;
	VELOCITY = vec3(0.0);
	CUSTOM.xyz = v;
}
