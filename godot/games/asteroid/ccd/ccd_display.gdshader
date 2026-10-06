// Turns a noiseless HDR "signal" frame into a CCD-like image: sky background, photon
// (Poisson ~ Gaussian) noise and read noise, then an asinh stretch like astronomers use.
// The same shader drives the main view and the circular loupe (view_center/view_span).
// Noise is a function of the image pixel and the frame seed, so a frame always looks
// the same no matter how it is zoomed.
shader_type canvas_item;

uniform sampler2D frame : filter_nearest;
uniform vec2 image_size = vec2(1536.0, 1024.0);
uniform vec2 view_center = vec2(0.5, 0.5);  // image uv shown at the centre
uniform vec2 view_span = vec2(1.0, 1.0);     // fraction of the image shown
uniform float seed = 1.0;
uniform float signal_scale = 1.0;  // < 1 while an exposure is still building up
uniform float bg = 0.003;          // sky background (signal units)
uniform float gain = 4000.0;       // larger = less photon noise
uniform float read_noise = 0.0008;
uniform float soft = 0.003;        // asinh knee
uniform float white = 1.2;
uniform bool circle = false;
uniform vec4 ring_color : source_color = vec4(1.0, 0.7, 0.28, 1.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float gauss(vec2 px) {
	float u1 = max(hash(px + seed * 17.13), 1e-6);
	float u2 = hash(px * 1.37 + seed * 3.71 + 11.0);
	return sqrt(-2.0 * log(u1)) * cos(6.2831853 * u2);
}

void fragment() {
	vec2 uv = view_center + (UV - 0.5) * view_span;
	vec2 px = floor(uv * image_size);
	float s = texture(frame, (px + 0.5) / image_size).r * signal_scale;
	float b = bg * max(signal_scale, 0.05);
	float v = s + b;
	float noisy = v + gauss(px) * sqrt(max(v, 0.0) / gain + read_noise * read_noise);
	float y = asinh(max(noisy - b, -soft) / soft) / asinh(white / soft);
	vec3 col = vec3(clamp(y, 0.0, 1.0));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		col = vec3(0.0);
	}
	float a = 1.0;
	if (circle) {
		float d = length(UV - 0.5);
		if (d > 0.5) {
			a = 0.0;
		} else if (d > 0.47) {
			col = ring_color.rgb;
		}
	}
	COLOR = vec4(col, a);
}
