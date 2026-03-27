shader_type spatial;

uniform vec3 base_color : source_color = vec3(1, 1, 1);      // 顶面颜色
uniform vec3 side_color : source_color = vec3(0.3, 0.3, 0.3); // 侧面颜色

// 底面颜色控制
uniform vec3 bottom_center_color : source_color = vec3(1.0, 0.8, 0.8); // 中心亮粉色
uniform vec3 bottom_edge_color : source_color = vec3(0.6, 0.2, 0.3);   // 四边暗粉色
uniform float gradient_power : hint_range(0.1, 5.0) = 1.0;            // 渐变强度（缩放感）

varying vec3 local_normal;

void vertex() {
    local_normal = NORMAL;
}

void fragment() {
    // 判断法线朝向
    if (local_normal.y < -0.5) {
        // --- 底面径向渐变逻辑 ---
        
        // 计算当前像素 UV 到中心点 (0.5, 0.5) 的距离
        // distance 会返回 0.0（中心）到 0.707（角点）之间的值
        float dist = distance(UV, vec2(0.5, 0.5));
        
        // 将距离映射到 0.0 - 1.0 范围
        // 乘以 2.0 是为了让渐变在到达边框中点时达到最大值
        float factor = clamp(dist * 2.0, 0.0, 1.0);
        
        // 使用 power 函数可以调整渐变的“软硬”度
        factor = pow(factor, gradient_power);
        
        // 根据因子在中心颜色和边缘颜色之间插值
        ALBEDO = mix(bottom_center_color, bottom_edge_color, factor);
        
    } else if (local_normal.y < 0.5) {
        ALBEDO = side_color; // 侧面
    } else {
        ALBEDO = base_color; // 顶面
    }
}