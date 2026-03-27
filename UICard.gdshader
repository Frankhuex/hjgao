shader_type canvas_item;

uniform bool is_solid_white = true;
uniform vec3 base_color : source_color = vec3(1.0, 1.0, 1.0); 
uniform vec3 bottom_center_color : source_color = vec3(1.0, 0.8, 0.8); // 中心亮粉色
uniform vec3 bottom_edge_color : source_color = vec3(0.6, 0.2, 0.3);   // 四边暗粉色
uniform float gradient_power : hint_range(0.1, 5.0) = 1.0;            // 渐变强度（缩放感）

void fragment() {
	if (is_solid_white) {
		COLOR = vec4(base_color, 1.0);
	} else {
	    float dist = distance(UV, vec2(0.5, 0.5));
	    float factor = clamp(dist * 2.0, 0.0, 1.0);
	    factor = pow(factor, gradient_power);
	    vec3 final_color = mix(bottom_center_color, bottom_edge_color, factor);
	    COLOR = vec4(final_color, 1.0); 
	}
}