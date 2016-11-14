import haxegon.*;


enum MainState {
    MainState_Game;
}

@:publicFields
class Main {
    static inline var width = 650;
    static inline var height = 500;

    static var state = MainState_Game;
    static var game: Game;

    function new() {
        Text.setfont("pixelFJ8", 8);
        #if flash
        Gfx.resize_screen(width, height, 1);
        #else 
        Gfx.resize_screen(width, height, 1);
        #end

        game = new Game();
    }

    function update() {
        switch (state) {
            case MainState_Game: game.update();
        }
    }
}
