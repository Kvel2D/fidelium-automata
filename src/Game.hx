import haxegon.*;
import haxe.ds.Vector;
import flash.net.SharedObject;
import Entity;

using haxegon.MathExtensions;

enum GameState {
    GameState_Start;
    GameState_Tutorial;
    GameState_Normal;
    GameState_Paused;
    GameState_Intervention;
    GameState_Announcement;
}

typedef Devotee = {
    name: String,
    sacrifice_timer: Int,
    evaluation_timer: Int,
    last_population: Int,
}

typedef Announcement = {
    text: String,
    image: String,
}

@:publicFields
class Game {
    static inline var map_width = 100;
    static inline var map_height = 100;

    var state = GameState_Start;
    var tutorial_stage = 0;
    static inline var intervention_timer_max = 300;
    static inline var evaluation_timer_max = 400;
    static inline var sacrifice_timer_max = 300;
    var intervention_timer = Std.int(intervention_timer_max * 0.7);
    var loser = "";
    var announcement_stack = new Array<Announcement>();

    var step_timer = 0;
    static inline var step_timer_fast = 4;
    static inline var step_timer_medium = 6;
    static inline var step_timer_slow = 8;
    var step_timer_max = step_timer_medium;

    var animal_names = new Array<String>();
    var animal_colors = new Map<String, Int>();
    var plant_names = new Array<String>();
    var entity_map = [for (x in 0...map_width) [for (y in 0...map_height) new Entity(x, y)]];
    var world_color = Col.WHITE;
    var populations = new Map<String, Int>();
    var devotion_chances = new Map<String, Int>();
    var reproduction_chances = new Map<String, Int>();

    var current_info_entity = new Entity(-1, -1);

    var current_spell = "";
    var mana = 10;
    var spells = [
    "LIGHTNING" => 1,
    "FUSE" => 10,
    "PLANT" => 2,
    ];

    var devotees = new Array<Devotee>();

    static inline var spells_y = 400;
    static inline var fusion_y = 300;
    static inline var devotees_y = 130;
    static inline var plant_hp_max = 50; //50

    var fusion_first = new Entity(-1, -1);
    var fusion_second = new Entity(-1, -1);
    var fusion_stage = 0;

    function new() {
        Gfx.load_image("pause");
        Gfx.load_image("play");
        Gfx.load_image("normal");
        Gfx.load_image("faster");
        Gfx.load_image("fastest");
        Gfx.load_image("LIGHTNING");
        Gfx.load_image("PLANT");
        Gfx.load_image("FUSE");

        GUI.set_pallete(Col.BLACK, Col.BLACK, Col.WHITE);

        var k = Random.int(1, Col.ALL.length - 1);
        world_color = Col.ALL[k];


        for (i in 0...5) {
            var name = generate_name();
            if (animal_names.indexOf(name) != -1) {
                continue;
            }
            animal_names.push(name);
            generate_animal_sprite(name);
        }

        for (i in 0...2) {
            var name = generate_name();
            if (animal_names.indexOf(name) != -1 || plant_names.indexOf(name) != -1) {
                continue;
            }
            plant_names.push(name);
            generate_plant_sprite(name);
        }


        var map = generate_map(0, map_width, 0, map_height, 0.45);
        // var map = generate_map(0, map_width, 0, map_height, 0.5);
        for (x in 0...map_width) {
            for (y in 0...map_height) {
                if (map[x][y] && entity_map[x][y].type == EntityType_None) {
                    entity_map[x][y].name = plant_names[0];
                    entity_map[x][y].type = EntityType_Plant;
                    entity_map[x][y].hp = plant_hp_max;
                }
            }
        }

        function make_animals(region_x: Int, region_y: Int, name: String, hp_max: Int, action: Int, 
            devotion_chance: Int, reproduction_chance: Int) {
            var w3 = Std.int(map_width / 3);
            var h3 = Std.int(map_height / 3);
            var map = generate_map(w3 * region_x, w3 * (region_x + 1), h3 * region_y, h3 * (region_y + 1));
            for (x in 0...map_width) {
                for (y in 0...map_height) {
                    if (map[x][y]) {
                        entity_map[x][y].type = EntityType_Animal;
                        entity_map[x][y].name = name;
                        entity_map[x][y].hp_max = hp_max;
                        entity_map[x][y].hp = Random.int(Std.int(hp_max / 3), hp_max);
                        entity_map[x][y].action_timer_max = action;
                    }
                }
            }
            devotion_chances.set(name, devotion_chance);
            reproduction_chances.set(name, reproduction_chance);
        }

        make_animals(0, 0, animal_names[0], Random.int(25, 45), Random.int(1, 6), Random.int(80, 100), Random.int(50, 95));
        make_animals(2, 0, animal_names[1], Random.int(25, 45), Random.int(1, 6), Random.int(80, 100), Random.int(50, 95));
        make_animals(0, 2, animal_names[2], Random.int(25, 45), Random.int(1, 6), Random.int(80, 100), Random.int(50, 95));
        make_animals(2, 2, animal_names[3], Random.int(25, 45), Random.int(1, 6), Random.int(80, 100), Random.int(50, 95));

        // Rabbits for testing
        // make_animals(0, 0, animal_names[0], 300, 1, 100, 100);
        // make_animals(2, 0, animal_names[1], 300, 1, 100, 100);
        // make_animals(2, 2, animal_names[2], 300, 1, 100, 100);
        // make_animals(0, 2, animal_names[3], 300, 1, 100, 100);

        // Count populations
        for (x in 0...map_width) {
            for (y in 0...map_height) {
                if (entity_map[x][y].type != EntityType_None) {
                    var name = entity_map[x][y].name;
                    if (populations.exists(name)) {
                        populations.set(name, populations.get(name) + 1);
                    } else {
                        populations.set(name, 1);
                    }
                }
            }
        }

        Gfx.create_image("background", 500, 500);
        Gfx.create_image("screen", 500, 500);
        update_background();
        update_screen();

        Gfx.create_image("fusion_preview", 4, 4);
    }

    function update_background() {
        Gfx.draw_to_image("background");
        Gfx.fill_box(0, 0, map_width * 5, map_height * 5, world_color);
        var entity: Entity;
        for (x in 0...map_width) {
            for (y in 0...map_height) {
                entity = entity_map[x][y];
                if (entity.type == EntityType_Plant) {
                    Gfx.draw_image(x * 5, y * 5, entity.name);
                }
            }
        }
        Gfx.draw_to_screen();
    }

    function update_screen() {
        Gfx.draw_to_image("screen");
        Gfx.draw_image(0, 0, "background");
        var entity: Entity;
        for (x in 0...map_width) {
            for (y in 0...map_height) {
                entity = entity_map[x][y];
                if (entity.type == EntityType_Animal) {
                    Gfx.draw_image(x * 5, y * 5, entity.name);
                }
            }
        }
        Gfx.draw_to_screen();
    }

    function update_background_one_cell(x: Int, y: Int) {
        Gfx.draw_to_image("background");
        Gfx.fill_box(x * 5, y * 5, 5, 5, world_color);
        Gfx.draw_to_screen();
    }

    function out_of_bounds(x: Int, y: Int): Bool {
        return x < 0 || x >= map_width || y < 0 || y >= map_height;
    }

    function generate_animal_sprite(name: String) {
        Gfx.create_image(name, 4, 4);
        Gfx.draw_to_image(name);
        var background = world_color; 
        while (background == world_color) {
            background = Col.ALL[Random.int(2, Col.ALL.length - 1)];
        }
        var foreground = background;
        while (foreground == background) {
            foreground = Col.ALL[Random.int(2, Col.ALL.length - 1)];
        }            

        var pixel_chance = Random.int(25, 100);

        var pixels_placed = 0;
        Gfx.clear_screen(background);
        while (pixels_placed == 0) {
            for (x in 0...2) {
                for (y in 0...4) {
                    var k = Random.chance(pixel_chance);
                    if (k) {
                        Gfx.set_pixel(x, y, foreground);
                        Gfx.set_pixel(3 - x, y, foreground);
                        pixels_placed++;
                        // don't feel in the whole square
                        if (pixels_placed >= 3) {
                            break;
                        }
                    }
                }
                if (pixels_placed >= 3) {
                    break;
                }
            }
        }

        animal_colors.set(name, foreground);

        Gfx.draw_to_screen();
    }

    function generate_plant_sprite(name: String) {
        Gfx.create_image(name, 4, 4);
        Gfx.draw_to_image(name);
        var foreground = world_color;
        while (foreground == world_color) {
            foreground = Col.ALL[Random.int(2, Col.ALL.length - 1)];
        }
        var pixel_chance = Random.int(25, 100);

        Gfx.clear_screen(world_color);
        for (x in 0...4) {
            for (y in 0...4) {
                var k = Random.chance(pixel_chance);
                if (k) {
                    Gfx.set_pixel(x, y, foreground);
                }
            }
        }

        Gfx.draw_to_screen();
    }

    var vowels = ['a', 'e', 'i', 'o', 'u'];
    var consonants = ['y', 'q', 'w', 'r', 't', 'p', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'z', 'x', 'c', 'v', 'b', 'n', 'm'];
    function generate_name(): String {
        var name = "";
        var consonant_first = Random.bool();
        if (consonant_first) {
            name += consonants[Random.int(0, consonants.length - 1)];
            name += vowels[Random.int(0, vowels.length - 1)];
        } else {
            name += vowels[Random.int(0, vowels.length - 1)];
            name += consonants[Random.int(0, consonants.length - 1)];
        }
        consonant_first = Random.bool();
        if (consonant_first) {
            name += consonants[Random.int(0, consonants.length - 1)];
            name += vowels[Random.int(0, vowels.length - 1)];
        } else {
            name += vowels[Random.int(0, vowels.length - 1)];
            name += consonants[Random.int(0, consonants.length - 1)];
        }
        return name.toUpperCase();
    }

    function generate_map(x_start: Int, x_end: Int, y_start: Int, y_end: Int, initial_chance: Float = 0.45): Vector<Vector<Bool>> {
        var map = Data.bool_2dvector(map_width, map_height);
        var map_old = Data.bool_2dvector(map_width, map_height);
        var death_limit = 4;
        var birth_limit = 3;
        var iterations = 6;

        function count_neighbours(map: Vector<Vector<Bool>>, x: Int, y: Int): Int {
            var count = 0;
            for (dx in -1...2) {
                for (dy in -1...2) {
                    var neighbour_x = x + dx;
                    var neighbour_y = y + dy;
                    if (dx == 0 && dy == 0) {
                        continue;
                    } else if (out_of_bounds(neighbour_x, neighbour_y)){
                        count++;
                    } else if (!map[neighbour_x][neighbour_y]) {
                        count++;
                    }
                }
            }
            return count;
        }

        

        for (x in x_start...x_end) {
            for (y in y_start...y_end) {
                if (Math.random() < initial_chance) {
                    map[x][y] = false;
                } else {
                    map[x][y] = true;
                }
            }
        }
        for (i in 0...iterations) {
            for (x in x_start...x_end) {
                for (y in y_start...y_end) {
                    map_old[x][y] = map[x][y];
                }
            }
            for (x in x_start...x_end) {
                for (y in y_start...y_end) {
                    var count = count_neighbours(map_old, x, y);

                    if (!map_old[x][y]) {
                        if (count < death_limit) {
                            map[x][y] = true;
                        } else {
                            map[x][y] = false;
                        }
                    } else {
                        if (count > birth_limit) {
                            map[x][y] = false;
                        } else {
                            map[x][y] = true;
                        }
                    }
                }
            }
        }

        return map;
    }



    var directions = [{x: -1, y: 0}, {x: 1, y: 0}, {x: 0, y: -1}, {x: 0, y: 1}];
    var directions_indices = [for (i in 0...4) i];
    function move_randomly(animal: Entity) {
        Random.shuffle(directions_indices);
        for (i in 0...directions_indices.length) {
            var dx = directions[directions_indices[i]].x;
            var dy = directions[directions_indices[i]].y;
            if (!out_of_bounds(animal.x + dx, animal.y + dy) 
                && entity_map[animal.x + dx][animal.y + dy].type == EntityType_None) 
            {
                var destination = entity_map[animal.x + dx][animal.y + dy];

                var eaten = false;
                for (dx2 in -1...2) {
                    if (eaten) {
                        break;
                    }
                    for (dy2 in -1...2) {
                        if (!out_of_bounds(destination.x + dx2, destination.y + dy2) 
                            && entity_map[destination.x + dx2][destination.y + dy2].type == EntityType_Plant) 
                        {
                            animal.hp += 5;
                            if (animal.hp > animal.hp_max) {
                                animal.hp = animal.hp_max;
                            }
                            eaten = true;
                            entity_map[destination.x + dx2][destination.y + dy2].hp--;
                            if (entity_map[destination.x + dx2][destination.y + dy2].hp <= 0) {
                                entity_map[destination.x + dx2][destination.y + dy2].delete();
                                update_background_one_cell(destination.x + dx2, destination.y + dy2);
                            }
                            break;
                        } 
                    }
                }


                destination.copy(animal);
                animal.delete();

                return;
            }
        }
    }

    function reproduce(animal: Entity) {
        Random.shuffle(directions_indices);
        for (i in 0...directions_indices.length) {
            var dx = directions[directions_indices[i]].x;
            var dy = directions[directions_indices[i]].y;
            if (!out_of_bounds(animal.x + dx, animal.y + dy) 
                && entity_map[animal.x + dx][animal.y + dy].type == EntityType_None) 
            {
                var destination = entity_map[animal.x + dx][animal.y + dy];
                destination.copy(animal);
                destination.hp = Std.int(animal.hp_max / 2);
                populations.set(animal.name, populations.get(animal.name) + 1);

                return;
            }
        }
    }

    function step() {
        // update animals
        for (x in 0...map_width) {
            for (y in 0...map_height) {
                var entity = entity_map[x][y];

                if (entity.type == EntityType_Animal) {
                    entity.action_timer++;

                    if (entity.action_timer > entity.action_timer_max) {
                        entity.action_timer = 0;
                        entity.hp--;

                        if (entity.hp <= 0) {
                            populations.set(entity.name, populations.get(entity.name) - 1);
                            entity.delete();
                        } else if (entity.hp * 1.0 / entity.hp_max > 0.95 
                        && Random.chance(reproduction_chances.get(entity.name))) { // NOTE: exact match or percentage?
                            reproduce(entity);
                        } else {
                            if (Random.chance(90)) {
                                move_randomly(entity);
                            }
                        }
                    }
                }
            }
        }
    }

    function message_box(text: String) {
        var width = 162;
        var height = 100;
        Gfx.fill_box(250 - width / 2, 250 - height / 2, width, height, Col.BLACK);
        Text.display(250 - Text.width(text) / 2, 220, text);
    }

    function make_sacrifice(animal: String): Int {
        var area_x = 0;
        var area_y = 0;
        var max_population = 0;
        var division = 20;
        for (x1 in 0...Std.int(map_width / division)) {
            for (y1 in 0...Std.int(map_height / division)) {
                var population = 0;
                for (x2 in (x1 * division)...((x1 + 1) * division)) {
                    for (y2 in (y1 * division)...((y1 + 1) * division)) {
                        if (entity_map[x2][y2].type == EntityType_Animal && entity_map[x2][y2].name == animal) {
                            population++;
                        }
                    }
                }
                if (population > max_population) {
                    max_population = population;
                    area_x = x1;
                    area_y = y1;
                }
            }
        }

        var number_sacrificed = 0;
        for (x2 in (area_x * division)...((area_x + 1) * division)) {
            for (y2 in (area_y * division)...((area_y + 1) * division)) {
                if (entity_map[x2][y2].type == EntityType_Animal && entity_map[x2][y2].name == animal) {
                    entity_map[x2][y2].delete();
                    populations.set(animal, populations.get(animal) - 1);
                    number_sacrificed++;
                }
            }
        }

        return number_sacrificed;
    }

    function render() {

        Gfx.draw_image(0, 0, "screen");

        var info_y = 30;
        Text.display(510, info_y, "INFO");
        if (current_info_entity.type != EntityType_None) {
            Gfx.draw_image(593, info_y + 22, current_info_entity.name);
        }
        switch (current_info_entity.type) {
            case EntityType_Animal: {
                Text.display(510, info_y + 15, 
                    'NAME :\n' +
                    'TYPE :\n' +
                    'FOOD :\n' +
                    'HEALTH :\n' +
                    'SPEED :\n' +
                    'REPRODUCTION :\n' +
                    'FAITH :\n' +
                    'POPULATION :'
                    );
                Text.display(600, info_y + 15, 
                    '${current_info_entity.name}\n' +
                    'ANIMAL\n' +
                    '${plant_names[0]}\n' +
                    '${current_info_entity.hp_max}\n' +
                    '${Std.int(10 / current_info_entity.action_timer_max)}\n' +
                    '${Std.int(reproduction_chances.get(current_info_entity.name) / 10)}\n' +
                    '${Std.int(devotion_chances.get(current_info_entity.name) / 10)}\n' +
                    '${populations.get(current_info_entity.name)}'
                    );
            }
            case EntityType_Plant: {
                Text.display(510, info_y + 15, 
                    'NAME :\n' +
                    'TYPE :\n' + 
                    'POPULATION :'
                    );
                Text.display(600, info_y + 15, 
                    '${current_info_entity.name}\n' +
                    'PLANT\n' + 
                    '${populations.get(current_info_entity.name)}'
                    );
            }
            default:
        }

        if (current_spell == "FUSE") {
            Text.display(510, fusion_y, "FUSION");
            if (mana < 10) {
                Text.display(510, fusion_y + 30, "Not enough mana");
            } else {
                switch (fusion_stage) {
                    case 0: Text.display(510, fusion_y + 30, "Pick first animal\nto fuse");
                    case 1: {
                        Gfx.draw_image(515, fusion_y + 20, fusion_first.name);
                        Text.display(520, fusion_y + 14, "+");
                        Text.display(510, fusion_y + 30, "Pick second animal\nto fuse");
                    }
                    case 2: {
                        Gfx.draw_image(515, fusion_y + 20, fusion_first.name);
                        Text.display(520, fusion_y + 14, "+");
                        Gfx.draw_image(530, fusion_y + 20, fusion_second.name);
                        Text.display(535, fusion_y + 14, "=");
                        Gfx.draw_image(545, fusion_y + 20, "fusion_preview");
                        Text.display(510, fusion_y + 30, "Place fused animal\non the map");
                    }
                }
            }
        }

        Text.display(510, devotees_y, "DEVOTEES");
        var current_devotees_y = devotees_y + 15;
        for (devotee in devotees) {
            Gfx.draw_image(515, current_devotees_y + 4, devotee.name);
            Text.display(520, current_devotees_y, devotee.name);
            current_devotees_y += 15;
        }

        Text.display(510, spells_y - 20, 'MANA: ${mana}');
        Text.display(510, spells_y, 'COST SPELLS');

        if (current_spell != "") {
            Gfx.draw_image(Mouse.x - Gfx.image_width(current_spell) / 2, 
                Mouse.y - Gfx.image_height(current_spell) / 2, current_spell);
        }
    }

    function cast_fuse(x: Int, y: Int) {
        if (!out_of_bounds(x, y)) {

            if (fusion_stage == 0 || fusion_stage == 1) {
                // Select entities to fuse
                var succesful = false;

                if (entity_map[x][y].type == EntityType_Animal) {
                    if (fusion_stage == 0) {
                        fusion_first.copy(entity_map[x][y]);
                    } else {
                        fusion_second.copy(entity_map[x][y]);
                    }
                    succesful = true;
                } else {
                    // Check around too because some animals are very fast
                    for (dx in -1...2) {
                        for (dy in -1...2) {
                            if (!out_of_bounds(x + dx, y + dy) && entity_map[x + dx][y + dy].type == EntityType_Animal) {
                                if (fusion_stage == 0) {
                                    fusion_first.copy(entity_map[x + dx][y + dy]);
                                } else {
                                    fusion_second.copy(entity_map[x + dx][y + dy]);
                                }
                                succesful = true;
                                break;
                            }
                        }
                    }
                }

                if (succesful && fusion_stage == 1) {
                    Gfx.draw_to_image("fusion_preview");
                    var background = animal_colors.get(fusion_first.name); 
                    var foreground = animal_colors.get(fusion_second.name);

                    var pixel_chance = Random.int(25, 100);

                    var pixels_placed = 0;
                    Gfx.clear_screen(background);
                    while (pixels_placed == 0) {
                        for (x in 0...2) {
                            for (y in 0...4) {
                                var k = Random.chance(pixel_chance);
                                if (k) {
                                    Gfx.set_pixel(x, y, foreground);
                                    Gfx.set_pixel(3 - x, y, foreground);
                                    pixels_placed++;
                                    // don't fill in the whole square
                                    if (pixels_placed >= 3) {
                                        break;
                                    }
                                }
                            }
                            if (pixels_placed >= 3) {
                                break;
                            }
                        }
                    }

                    Gfx.draw_to_screen();
                }

                if (succesful) {
                    fusion_stage++;
                }
            } else if (fusion_stage == 2) {
                // Place fused entity
                var succesful = false;

                var map = generate_map(
                    Std.int(Math.max(0, x - 10)), Std.int(Math.min(map_width, x + 10)), 
                    Std.int(Math.max(0, y - 10)), Std.int(Math.min(map_width, y + 10)), 
                    0.3);

                var name = fusion_first.name.substr(0, 2) + fusion_second.name.substr(2, 2); 
                var avg_hp_max = Std.int((fusion_first.hp_max + fusion_second.hp_max) / 2);
                var hp_max = Random.int(Std.int(avg_hp_max * 0.8), Std.int(avg_hp_max * 1.25));
                var avg_action_timer_max = Std.int((fusion_first.action_timer_max + fusion_second.action_timer_max) / 2);
                var action_timer_max = Random.int(Std.int(avg_action_timer_max * 0.75), Std.int(avg_action_timer_max * 1.2));
                if (action_timer_max < 1) {
                    action_timer_max = 1;
                }

                var reproduction1 = reproduction_chances.get(fusion_first.name);
                var reproduction2 = reproduction_chances.get(fusion_second.name);
                var avg_reproduction = Std.int((reproduction1 + reproduction2) / 2);
                var reproduction = Random.int(Std.int(avg_reproduction * 0.8), Std.int(avg_reproduction * 1.25));
                if (reproduction > 100) {
                    reproduction = 100;
                }
                var devotion1 = devotion_chances.get(fusion_first.name);
                var devotion2 = devotion_chances.get(fusion_second.name);
                var avg_devotion = Std.int((devotion1 + devotion2) / 2);
                var devotion = Random.int(Std.int(avg_devotion * 0.8), Std.int(avg_devotion * 1.25));
                if (devotion > 100) {
                    devotion = 100;
                }

                var population = 0;
                for (dx in -10...11) {
                    for (dy in -10...11) {
                        if (!out_of_bounds(x + dx, y + dy) && map[x + dx][y + dy]) {
                            var entity = entity_map[x + dx][y + dy];
                            if (entity.type != EntityType_None) {
                                populations.set(entity.name, populations.get(entity.name) - 1);
                            }
                            entity.delete();

                            entity.type = EntityType_Animal;
                            entity.name = name;
                            entity.hp_max = hp_max;
                            entity.hp = Random.int(Std.int(hp_max / 3), hp_max);
                            entity.action_timer_max = action_timer_max;

                            population++;
                        }
                    }
                }
                devotion_chances.set(name, devotion);
                reproduction_chances.set(name, reproduction);
                populations.set(name, population);
                update_background();

                Gfx.create_image(name, 4, 4);
                Gfx.draw_to_image(name);
                Gfx.draw_image(0, 0, "fusion_preview");
                Gfx.draw_to_screen();

                fusion_stage = 0;
                mana -= spells[current_spell];
                current_spell = ""; // assume that we want to cancel fusion after we're done
            }
        }
    }

    function cast_lightning(x: Int, y: Int) {
        if (!out_of_bounds(x, y)) {
            for (dx in -10...11) {
                for (dy in -10...11) {
                    if (!out_of_bounds(x + dx, y + dy)) {
                        var entity = entity_map[x + dx][y + dy];
                        if (entity.type == EntityType_Animal) {
                            populations.set(entity.name, populations.get(entity.name) - 1);
                            entity.delete();
                        }
                    }
                }
            }
            mana -= spells[current_spell];
        }
    }

    function cast_plant(x: Int, y: Int) {
        if (!out_of_bounds(x, y)) {
            var map = generate_map(
                Std.int(Math.max(0, x - 10)), Std.int(Math.min(map_width, x + 10)), 
                Std.int(Math.max(0, y - 10)), Std.int(Math.min(map_width, y + 10)), 
                0.35);
            for (dx in -10...11) {
                for (dy in -10...11) {
                    if (!out_of_bounds(x + dx, y + dy) && map[x + dx][y + dy]) {
                        var entity = entity_map[x + dx][y + dy];
                        if (entity.type != EntityType_None) {
                            populations.set(entity.name, populations.get(entity.name) - 1);
                        }
                        entity.delete();

                        entity.type = EntityType_Plant;
                        entity.name = plant_names[0];
                        entity.hp = plant_hp_max;
                        populations.set(entity.name, populations.get(entity.name) + 1);
                    }
                }
            }
            update_background();
            mana -= spells[current_spell];
        }
    }

    function update_normal() {
        step_timer--;
        if (step_timer <= 0) {
            step_timer = step_timer_max;
            step();

            update_screen();

            // Check for extinct species
            var removed_names = new Array<String>();
            for (name in populations.keys()) {
                // plants can get extinct too, makes sense
                if (populations.get(name) <= 0) {
                    var announcement: Announcement = {
                        text: '${name} has gone\nextinct!',
                        image: name,
                    }
                    announcement_stack.push(announcement);

                    // Remove extinct animal from fusion if it's selected
                    if (fusion_first.name == name) {
                        fusion_stage = 0;
                    } else if (fusion_second.name == name) {
                        fusion_stage = 1;
                    }

                    removed_names.push(name);
                }
            }
            for (name in removed_names) {
                populations.remove(name);

                for (devotee in devotees) {
                    if (devotee.name == name) {
                        devotees.remove(devotee);
                        break;
                    }
                }
            }

            // Intervention: animals with low population ask for help
            intervention_timer--;
            if (intervention_timer <= 0) {
                intervention_timer = Random.int(Std.int(intervention_timer_max * 0.75), Std.int(intervention_timer_max * 1.25));

                loser = "";
                var loser_population = 1000000;
                for (name in populations.keys()) {
                    // not devoted already, not a plant, low population
                    var devoted_already = false;
                    for (devotee in devotees) {
                        if (devotee.name == name) {
                            devoted_already = true;
                            break;
                        }
                    }
                    if (!devoted_already 
                        && animal_names.indexOf(name) != -1 
                        && populations[name] < loser_population
                        && Random.chance(devotion_chances.get(name))) 
                    {
                        loser = name;
                        loser_population = populations[loser];
                    }
                }

                if (loser != "") {
                    state = GameState_Intervention;
                }
            }


            // Devoted animals make sacrifices
            var removed_devotees = new Array<Devotee>();
            for (devotee in devotees) {

                // Evaluation: if god doesn't help animals or harm them, animals lose faith
                // if god helps animals, animals recover faith
                devotee.evaluation_timer--;
                if (devotee.evaluation_timer <= 0) {
                    devotee.evaluation_timer = Random.int(Std.int(evaluation_timer_max * 0.75), Std.int(evaluation_timer_max * 1.25));
                    var current_population = populations.get(devotee.name);
                    var d_population = current_population - devotee.last_population;
                    devotee.last_population = current_population;

                    var devotion = devotion_chances.get(devotee.name);
                    var decrease_threshold = -0.2;
                    if (devotion > 90) {
                        decrease_threshold = -0.4;
                    } else if (devotion > 70) {
                        decrease_threshold = -0.3;
                    }
                    // lose faith if population decreases a lot
                    // gain faith otherwise
                    if (d_population / devotee.last_population < decrease_threshold) {
                        var announcement: Announcement = {
                            text: '${devotee.name} has lost\nfaith in you!\nThey will not make\nsacrifices to you\nanymore.',
                            image: devotee.name,
                        }
                        announcement_stack.push(announcement);
                        removed_devotees.push(devotee);
                        // decrease chance for next devotion
                        devotion_chances.set(devotee.name, Std.int(devotion_chances.get(devotee.name) * 0.3)); 
                    } else {
                        devotion_chances.set(devotee.name, Std.int(devotion_chances.get(devotee.name) * 1.1)); 
                    }
                }

                // Sacrifice for mana
                devotee.sacrifice_timer--;
                if (devotee.sacrifice_timer <= 0) {
                    devotee.sacrifice_timer = Random.int(Std.int(sacrifice_timer_max * 0.75), Std.int(sacrifice_timer_max * 1.25));
                    var number_sacrificed = make_sacrifice(devotee.name);
                    var mana_added = Std.int(number_sacrificed / 5);
                    mana += mana_added;

                    var announcement: Announcement = {
                        text: '${devotee.name} sacrifice $number_sacrificed of\nthemselves to you.\nYou gain ${mana_added} mana.',
                        image: devotee.name,
                    }
                    announcement_stack.push(announcement);
                }
            }

            for (devotee in removed_devotees) {
                devotees.remove(devotee);
            }
        }

        if (announcement_stack.length != 0) {
            state = GameState_Announcement;
        }


        GUI.image_button(510, 10, "pause", function() state = GameState_Paused);
        GUI.image_button(525, 10, "normal", function() step_timer_max = step_timer_slow);
        GUI.image_button(537, 10, "faster", function() step_timer_max = step_timer_medium);
        GUI.image_button(549, 10, "fastest", function() step_timer_max = step_timer_fast);

        var current_spells_y = spells_y + 20;
        for (spell in spells.keys()) {
            Text.display(520, current_spells_y, '${spells[spell]}', Col.WHITE);
            GUI.text_button(542, current_spells_y, spell, function() current_spell = spell);
            current_spells_y += 20;
        }
        GUI.text_button(542, current_spells_y, "CANCEL", function() current_spell = "");

        
        render();

        if (Mouse.left_click()) {
            var x = Std.int(Mouse.x / 5);
            var y = Std.int(Mouse.y / 5);
            if (current_spell == "") {
                if (!out_of_bounds(x, y) && entity_map[x][y].type != EntityType_None) {
                    current_info_entity.copy(entity_map[x][y]);
                } else {
                    // Check around too because some animals are very fast
                    for (dx in -1...2) {
                        for (dy in -1...2) {
                            if (!out_of_bounds(x + dx, y + dy) && entity_map[x + dx][y + dy].type != EntityType_None) {
                                current_info_entity.copy(entity_map[x + dx][y + dy]);
                                break;
                            }
                        }
                    }
                }
            } else {
                if (spells[current_spell] <= mana) {
                    switch (current_spell) {
                        case "LIGHTNING": {
                            cast_lightning(x, y);
                        }
                        case "PLANT": {
                            cast_plant(x, y);
                        }
                        case "FUSE": {
                            cast_fuse(x, y);
                        }
                    }
                }
            }
        } else if (Mouse.right_click()) {
            current_spell = "";
            fusion_stage = 0;
        }
    }

    function check_for_info() {
        if (Mouse.left_click() && current_spell == "") {
            var x = Std.int(Mouse.x / 5);
            var y = Std.int(Mouse.y / 5);
            if (!out_of_bounds(x, y) && entity_map[x][y].type != EntityType_None) {
                current_info_entity.copy(entity_map[x][y]);
            } else {
                // Check around too because some animals are very fast
                for (dx in -1...2) {
                    for (dy in -1...2) {
                        if (!out_of_bounds(x + dx, y + dy) && entity_map[x + dx][y + dy].type != EntityType_None) {
                            current_info_entity.copy(entity_map[x + dx][y + dy]);
                            break;
                        }
                    }
                }
            }
        } else if (Mouse.right_click()) {
            current_spell = "";
            fusion_stage = 0;
        }
    }

    function update_paused() {
        render();

        GUI.image_button(510, 10, "play", function() state = GameState_Normal);
        GUI.image_button(525, 10, "normal", function() step_timer_max = step_timer_slow);
        GUI.image_button(537, 10, "faster", function() step_timer_max = step_timer_medium);
        GUI.image_button(549, 10, "fastest", function() step_timer_max = step_timer_fast);

        var current_spells_y = spells_y + 20;
        for (spell in spells.keys()) {
            Text.display(520, current_spells_y, '${spells[spell]}', Col.WHITE);
            GUI.text_button(542, current_spells_y, spell, function() {});
            current_spells_y += 20;
        }
        GUI.text_button(542, current_spells_y, "CANCEL", function() {});

        check_for_info();
    }

    function update_start() {
        render();
        message_box("Tutorial?");
        GUI.text_button(220, 250, "Yes", function() state = GameState_Tutorial);
        GUI.text_button(260, 270, "No", function() state = GameState_Normal);

        GUI.image_button(510, 10, "play", function(){});
        GUI.image_button(525, 10, "normal", function(){});
        GUI.image_button(537, 10, "faster", function(){});
        GUI.image_button(549, 10, "fastest", function(){});

        var current_spells_y = spells_y + 20;
        for (spell in spells.keys()) {
            Text.display(520, current_spells_y, '${spells[spell]}', Col.WHITE);
            GUI.text_button(542, current_spells_y, spell, function() {});
            current_spells_y += 20;
        }
        GUI.text_button(542, current_spells_y, "CANCEL", function() {});
    }

    function update_tutorial() {
        render();
        switch (tutorial_stage) {
            case 0: message_box("Click on things\non the map to get\nmore info");
            case 1: message_box("Use controls on\nthe sidebar to start,\npause and change speed");
            case 2: message_box("Use spells by selecting\na spell on the sidebar\n");
            case 3: message_box("Cancel spells by right\nclicking\n");
            case 4: message_box("Do");
            case 5: message_box("Have");
            case 6: message_box("Fun");
            default: {
                message_box("Fun");
                state = GameState_Normal;
            }
        }
        GUI.text_button(280, 280, "Next", function() tutorial_stage++);

        GUI.image_button(510, 10, "play", function(){});
        GUI.image_button(525, 10, "normal", function(){});
        GUI.image_button(537, 10, "faster", function(){});
        GUI.image_button(549, 10, "fastest", function(){});

        var current_spells_y = spells_y + 20;
        for (spell in spells.keys()) {
            Text.display(520, current_spells_y, '${spells[spell]}', Col.WHITE);
            GUI.text_button(542, current_spells_y, spell, function() {});
            current_spells_y += 20;
        }
        GUI.text_button(542, current_spells_y, "CANCEL", function() {});

        check_for_info();
    }

    function update_intervention() {
        render();
        var intervention_text = '${loser} are praying\nfor your help.\nWill you answer\ntheir call?';
        message_box(intervention_text);
        Gfx.draw_image(250 - Text.width(intervention_text) / 2 - 10, 224, loser);
        GUI.text_button(220, 265, "Yes", function() {
            var devotee: Devotee = {
                name: loser,
                sacrifice_timer: sacrifice_timer_max,
                evaluation_timer: evaluation_timer_max,
                last_population: populations.get(loser),
            }
            devotees.push(devotee);
            loser = "";
            state = GameState_Normal;
        });
        GUI.text_button(260, 280, "No", function() state = GameState_Normal);

        GUI.image_button(510, 10, "play", function(){});
        GUI.image_button(525, 10, "normal", function(){});
        GUI.image_button(537, 10, "faster", function(){});
        GUI.image_button(549, 10, "fastest", function(){});

        var current_spells_y = spells_y + 20;
        for (spell in spells.keys()) {
            Text.display(520, current_spells_y, '${spells[spell]}', Col.WHITE);
            GUI.text_button(542, current_spells_y, spell, function() {});
            current_spells_y += 20;
        }
        GUI.text_button(542, current_spells_y, "CANCEL", function() {});

        check_for_info();
    }

    function update_announcement() {
        render();

        var announcement = announcement_stack[0];

        message_box(announcement.text);
        Gfx.draw_image(250 - Text.width(announcement.text) / 2 - 10, 224, '${announcement.image}');
        GUI.text_button(260, 275, "OK", function() {
            announcement_stack.remove(announcement);
            state = GameState_Normal;
        });

        GUI.image_button(510, 10, "play", function(){});
        GUI.image_button(525, 10, "normal", function(){});
        GUI.image_button(537, 10, "faster", function(){});
        GUI.image_button(549, 10, "fastest", function(){});

        var current_spells_y = spells_y + 20;
        for (spell in spells.keys()) {
            Text.display(520, current_spells_y, '${spells[spell]}', Col.WHITE);
            GUI.text_button(542, current_spells_y, spell, function() {});
            current_spells_y += 20;
        }
        GUI.text_button(542, current_spells_y, "CANCEL", function() {});

        check_for_info();
    }

    function update() {
        switch (state) {
            case GameState_Start: update_start();
            case GameState_Tutorial: update_tutorial();
            case GameState_Normal: update_normal();
            case GameState_Paused: update_paused();
            case GameState_Intervention: update_intervention();
            case GameState_Announcement: update_announcement();
        }
    }
}
