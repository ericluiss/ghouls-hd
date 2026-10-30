// Escala "sharp bilinear": pixels nítidos e quadrados em qualquer escala,
// sem o tremido do nearest em escalas não inteiras (ex.: 4.82x para 1080p).
// Scanlines opcionais, desligadas por padrão para ficar idêntico ao original.
shader_type canvas_item;

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 texel = UV * tex_size;
	// Quantos pixels de tela cada pixel do console ocupa (derivada = funciona em qualquer resolução).
	vec2 scale = max(1.0 / fwidth(texel), vec2(1.0));

	vec2 texel_floor = floor(texel);
	vec2 center_dist = fract(texel) - 0.5;
	vec2 region = 0.5 - 0.5 / scale;
	vec2 f = (center_dist - clamp(center_dist, -region, region)) * scale + 0.5;
	vec3 color = texture(TEXTURE, (texel_floor + f) * TEXTURE_PIXEL_SIZE).rgb;

	if (scanline_strength > 0.0) {
		float line = sin(fract(texel.y) * 3.14159265);
		color *= mix(1.0, 0.35 + 0.65 * line, scanline_strength);
	}
	COLOR = vec4(color, 1.0);
}
