package haxegon;

using haxegon.MathExtensions;


@:publicFields
class GUI {
	static var x: Float = 0;
	static var y: Float = 0;
	static var slider_cache = {hash: "", dragged: false};

	static var button_off_color = Col.GRAY;
	static var button_on_color = Col.PINK;
	static var button_text_color = Col.WHITE;
	static var slider_background_color = Col.GRAY; 
	static var slider_handle_color = Col.PINK;
	static var slider_text_color = Col.WHITE;


	static function set_pallete(passive: Int, active: Int, text: Int) {
		button_off_color = passive;
		slider_background_color = passive;
		
		button_on_color = active;
		slider_handle_color = active;

		button_text_color = text;
		slider_text_color = text;
	}

	static function image_button(x: Float, y: Float, image: String, button_function: Void->Void) {
		var image_width = Gfx.image_width(image);
		var image_height = Gfx.image_height(image);
		var button_width = image_width * 1.1;
		var button_height = image_height * 1.1;

		if (Mouse.left_click() && Math.point_box_intersect(Mouse.x, Mouse.y, x, y, button_width, button_height)) {
			button_function();
		}
		Gfx.draw_image(x, y, image);
	}

	static function auto_text_button(text: String, button_function: Void->Void, skips: Int = 0) {
		var text_height = Text.height();
		var button_height = text_height * 1.25;
		y += (button_height + 2) * (skips);

		text_button(x, y, text, button_function);

		y += (button_height + 2);
	}

	static function text_button(button_x: Float, button_y: Float, text: String, button_function: Void->Void) {
		var text_width = Text.width(text);
		var text_height = Text.height();
		var button_width = text_width * 1.1;
		var button_height = text_height * 1.25;

		if (Math.point_box_intersect(Mouse.x, Mouse.y, button_x, button_y, button_width, button_height)) {
			Gfx.fill_box(button_x, button_y, button_width, button_height, button_on_color);
			if (Mouse.left_click()) {
				button_function();
			}
		} else {
			Gfx.fill_box(button_x, button_y, button_width, button_height, button_off_color);
		}
		Text.display(button_x, button_y, text, button_text_color);
	}

	static function slider(text: String, set_function: Float->Void, current: Float, min: Float, max: Float, 
		handle_width: Float, area_width: Float, skips: Int = 0) {
		var text_width = Text.width(text);
		var text_height = Text.height();
		var height = text_height * 1.25;
		y += (height + 2) * (skips);


		Gfx.fill_box(x, y, area_width + text_width * 1.2, height, slider_background_color);
		Gfx.fill_box(x + area_width * (current - min) / (max - min), y + height * 0.05, handle_width, height * 0.9, slider_handle_color);

		var hash = '${text}_${x}_${y}';
		if (slider_cache.hash == hash) {
			if (slider_cache.dragged && Mouse.left_held()) {
				var value = current;
				if (Mouse.x < x) {
					value = min;
				} else if (Mouse.x > x + area_width) {
					value = max;
				} else {
					value = (Mouse.x - x) / area_width * (max - min) + min; 
				}
				set_function(value);
			} else {
				slider_cache.hash = "";
			}
		} else {
			if (Mouse.left_click() && Math.point_box_intersect(Mouse.x, Mouse.y, x - area_width * 0.1, y - height * 0.5, area_width * 1.2, height * 1.1)) {
				slider_cache.hash = hash;
				slider_cache.dragged = true;
			}
		}

		var value_string = Math.fixed_float(current, 3);
		Text.display(x + area_width / 2 - Text.width(value_string) / 2, y, value_string, Col.WHITE);
		Text.display(x + area_width + handle_width, y, text);

		y += (height + 2);
	}

	function new(){}
}