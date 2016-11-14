import haxegon.*;

enum EntityType {
    EntityType_None;
    EntityType_Animal;
    EntityType_Plant;
    EntityType_Rock;
}

@:publicFields
class Entity {
    var x = 0;
    var y = 0;
    var name = "";
    var action_timer = 0;
    var action_timer_max = 0;
    var type = EntityType_None;
    var hp = 0;
    var hp_max = 0;

    function new(x: Int, y: Int) {
    	this.x = x;
        this.y = y;
    }

    function copy(entity: Entity) {
        this.name = entity.name;
        this.action_timer = entity.action_timer;
        this.action_timer_max = entity.action_timer_max;
        this.type = entity.type;
        this.hp = entity.hp;
        this.hp_max = entity.hp_max;
    }

    function delete() {
        this.type = EntityType_None;
    }
}