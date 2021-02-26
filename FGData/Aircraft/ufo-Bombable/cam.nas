####   Aerotro's Flightgear Cam  ####

var CAM = props.globals.getNode("/sim/cam");

var MPS = 0.514444444;
var sin = func(v) math.sin(v * D2R);
var cos = func(v) math.cos(v * D2R);
var atan2 = func(v, w) math.atan2(v, w) * R2D;

var panel_dialog = gui.Dialog.new("/sim/gui/dialogs/cam/panel/dialog",
        "Aircraft/ufo-Bombable/Dialogs/cam.xml");
var callsign_dialog = gui.Dialog.new("/sim/gui/dialogs/cam/select/dialog",
        "Aircraft/ufo-Bombable/Dialogs/callsign.xml");

var maxspeedN = props.globals.getNode("engines/engine/speed-max-mps");
var speed = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000];
var current = 5;
var maxspeed = speed[current];
var cam_view = nil;
var view_number = 0;
var min_alt_agl = 5.0; # meter

var targetN = nil;
var target = geo.Coord.new();
var self = nil;
var aircraft_list = [];


var goal_headingN = props.globals.getNode("sim/current-view/goal-heading-offset-deg");
var goal_pitchN = props.globals.getNode("sim/current-view/goal-pitch-offset-deg");
var goal_rollN = props.globals.getNode("sim/current-view/goal-roll-offset-deg");


var mode = {
    chase : props.globals.getNode("/sim/cam/chase"),
    focus : props.globals.getNode("/sim/cam/focus"),
    speed : props.globals.getNode("/sim/cam/speed"),
    alt   : props.globals.getNode("/sim/cam/alt"),
    lock  : props.globals.getNode("/sim/cam/lock"),
};


var lowpass = {
    viewheading : aircraft.angular_lowpass.new(0.2),
    viewpitch   : aircraft.lowpass.new(0.1),
    viewroll    : aircraft.lowpass.new(0.1),

    hdg         : aircraft.angular_lowpass.new(0.6),
    alt         : aircraft.lowpass.new(3),
    speed       : aircraft.lowpass.new(2),
    throttle    : aircraft.lowpass.new(0.3),
};


controls.flapsDown = func(x) {
    if (!x)
        return;
    elsif (x < 0 and current > 0)
        current -= 1;
    elsif (x > 0 and current < size(speed) - 1)
        current += 1;

    maxspeed = speed[current];
}


#var throttle = 0;
#controls.throttleAxis = func(n) {
#	val = n.getNode("setting").getValue();
#	if (size(arg) > 0)
#		val = -val;
#	throttle = (1 - val) * 0.5;
#	props.setAll("/controls/engines/engine", "throttle", lowpass.throttle.filter(throttle));
#}


# sort function
var by_callsign = func(a, b) {
    cmp(a.getNode("callsign").getValue(), b.getNode("callsign").getValue());
}


var update_aircraft_list = func {
    var ac = [];
    var n = props.globals.getNode("/ai/models");

    if (getprop("/sim/cam/target-ai"))
        ac ~= n.getChildren("aircraft") ~ n.getChildren("tanker");
    if (getprop("/sim/cam/target-mp"))
        ac ~= n.getChildren("multiplayer");

    aircraft_list = [];

    foreach (var model; ac) {
        var model_node = model.getNode("valid");
        if (model_node != nil and model_node.getBoolValue()) {
            append(aircraft_list, model);
        }
        }

    aircraft_list = sort(aircraft_list, by_callsign);
}


var update = func {
    # data acquisition
    target.set_latlon(
        targetN.getNode("position/latitude-deg").getValue(),
        targetN.getNode("position/longitude-deg").getValue(),
        targetN.getNode("position/altitude-ft").getValue() * FT2M);

    self = geo.aircraft_position();

if (0) {
    if (mode.lock.getValue()) {
        self.set(target);
        self.apply_course_distance(rel.course, rel.distance);
        self.set_alt(target.alt() + rel.alt);
        setprop("/position/latitude-deg", self.lat());
        setprop("/position/longitude-deg", self.lon());
        setprop("/position/altitude-ft", self.alt() * M2FT);
    }
}

    var self_heading = getprop("/orientation/heading-deg");
    var self_pitch = getprop("/orientation/pitch-deg");
    var self_roll = getprop("/orientation/roll-deg");

    # check whether to unlock altitude/heading
    if (abs(self_pitch) > 2)
        mode.alt.setValue(0);
    if (abs(self_roll) > 2)
        mode.chase.setValue(0);

    # calculate own altitude
    var min_alt_asl = target.alt() - getprop("/position/altitude-agl-ft") * FT2M + min_alt_agl;
    if (self.alt() <= min_alt_asl)
        setprop("/position/altitude-ft", lowpass.alt.filter(min_alt_asl) * M2FT);
    elsif (mode.alt.getValue())
        setprop("/position/altitude-ft", lowpass.alt.filter(target.alt()) * M2FT);
    else
        lowpass.alt.filter(self.alt());

    # calculate position relative to target
    var distance = self.direct_distance_to(target);
    if (distance < 1) {
        var course = targetN.getNode("orientation/true-heading-deg").getValue();
        mode.focus.setValue(0);
        mode.chase.setValue(0);
    } else {
        var course = self.course_to(target);
    }
    var elevation = atan2(target.alt() - lowpass.alt.get(), distance);

    # set own heading
    if (mode.chase.getValue()){
    var voff=targetN.getNode("radar/v-offset").getValue();
    if(voff >60 or voff < -60){mode.chase.setValue(0);}
    var dist=targetN.getNode("radar/range-nm").getValue();
    if(dist < 0.01){mode.chase.setValue(0);}
    setprop("/orientation/heading-deg", self_heading = lowpass.hdg.filter(course));
    }
    # calculate focus view direction
    if (mode.focus.getValue()) {
        var h = lowpass.viewheading.filter(self_heading - course);
        var p = elevation - self_pitch * cos(h);
        var r = -self_roll * sin(h);
        goal_headingN.setValue(h);
        goal_pitchN.setValue(lowpass.viewpitch.filter(p));
        goal_rollN.setValue(lowpass.viewroll.filter(r));
    }

    # calculate own speed
    if (mode.speed.getValue())
        maxspeed = targetN.getNode("velocities/true-airspeed-kt").getValue() * MPS * 2;
    else
        maxspeed = speed[current];
    maxspeedN.setDoubleValue(lowpass.speed.filter(maxspeed));
}


var loop = func {
    if (view_number == cam_view and targetN != nil)
        update();

    settimer(loop, 0);
}


var select_aircraft = func(index) {
    update_aircraft_list();

    var number = size(aircraft_list);
    var name = "";
    targetN = nil;

    if (number) {
        if (index < 0)
            index = number - 1;
        elsif (index >= number)
            index = 0;

        targetN = aircraft_list[index];
        name = targetN.getNode("callsign").getValue();
    }
    setprop("/sim/cam/target-number", index);
    setprop("/sim/cam/target-name", name);
}


var target_name_changed = func() {

    var target_name = getprop("/sim/cam/target-name");

    if (target_name == nil or cmp(target_name, "") == 0)
        return;

    forindex (var i; aircraft_list) {
        if (cmp(target_name,
            aircraft_list[i].getNode("callsign").getValue()) == 0) {
            if (i != getprop("/sim/cam/target-number")) {
                # found the index for the new target-name
                select_aircraft(i);
            }

            return;
        }
    }

    # no matches, select the current index again
    update_aircraft();
}


# called from the dialog
var goto_target = func {
    targetN != nil or return;
    self != nil or return;
    var lat = targetN.getNode("position/latitude-deg").getValue();
    var lon = targetN.getNode("position/longitude-deg").getValue();
    var alt = targetN.getNode("position/altitude-ft").getValue() * FT2M;
    var speed = targetN.getNode("velocities/true-airspeed-kt").getValue() * MPS * 2;
    var course = targetN.getNode("orientation/true-heading-deg").getValue();
    self.set_latlon(lat, lon, alt).apply_course_distance(course + 180, 100);
    setprop("/position/latitude-deg", self.lat());
    setprop("/position/longitude-deg", self.lon());
    lowpass.alt.set(self.alt());
    lowpass.speed.set(speed);
    mode.chase.setValue(1);
    mode.focus.setValue(1);
    mode.alt.setValue(1);
    mode.speed.setValue(1);
    maxspeed = speed * 2;
#	props.setAll("/controls/engines/engine", "throttle", lowpass.throttle.set(0.5));
}

var update_goto = func {
    if (!getprop("/sim/cam/goto"))
        return;

    goto_target();
    setprop("/sim/cam/goto", 0);
}

var update_aircraft = func {
    select_aircraft(getprop("/sim/cam/target-number"));
}

var ai_removed = func {
    var node_str = getprop("/ai/models/model-removed") ~ "/callsign";
    var target_name = getprop(node_str);
    if (cmp(target_name, getprop("/sim/cam/target-name")) == 0) {
        update_aircraft();
    }
}

setlistener("/sim/cam/target-number", update_aircraft);
setlistener("/sim/cam/target-name", target_name_changed);
setlistener("/sim/cam/target-ai", update_aircraft);
setlistener("/sim/cam/target-mp", update_aircraft);
setlistener("/sim/cam/goto", update_goto);
setlistener("/ai/models/model-removed", ai_removed);

setlistener("/sim/current-view/view-number", func(n) {
    view_number = n.getValue();
    if (view_number == cam_view)
        panel_dialog.open();
    else
        panel_dialog.close();
});


if (0) {
var rel = { course: 0, distance: 0, alt: 0 };
setlistener("/sim/cam/lock", func(n) {
    if (n.getValue()) {
        rel.course = target.course_to(self);
        rel.distance = target.distance_to(self);
        rel.alt = self.alt() - target.alt();
    }
});
}


setlistener("/sim/signals/fdm-initialized", func {
    var views = props.globals.getNode("/sim").getChildren("view");
    forindex (var i; views)
        if (views[i].getNode("name").getValue() == "Cam View")
            cam_view = i;

    setprop("/sim/current-view/view-number", cam_view);
    setprop("/engines/engine/speed-max-mps", 500);
    update_aircraft();
    loop();
});


