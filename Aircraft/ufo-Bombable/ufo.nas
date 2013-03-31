
setlistener("/sim/panel/visibility", func(n) {
	setprop("/instrumentation/radar/serviceable", n.getValue());
}, 1);


var gear_key_down = 0;
controls.gearDown = func(x) gear_key_down = x != 0;



# maximum speed -----------------------------------------------------------------------------------

var maxspeed = props.globals.getNode("engines/engine/speed-max-mps");
var speed = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000];
var current = 7;


controls.flapsDown = func(x) {
	if (!x)
		return;
	elsif (x < 0 and current > 0)
		current -= 1;
	elsif (x > 0 and current < size(speed) - 1)
		current += 1;

	var s = speed[current];
	maxspeed.setDoubleValue(s);
	gui.popupTip("Max. Speed " ~ s ~ " m/s");
}



# dialogs -----------------------------------------------------------------------------------------

var status_dialog = gui.Dialog.new("/sim/gui/dialogs/ufo/status/dialog", "Aircraft/ufo-Bombable/Dialogs/status.xml");
var select_dialog = gui.Dialog.new("/sim/gui/dialogs/ufo/select/dialog", "Aircraft/ufo-Bombable/Dialogs/select.xml");
var adjust_dialog = gui.Dialog.new("/sim/gui/dialogs/ufo/adjust/dialog", "Aircraft/ufo-Bombable/Dialogs/adjust.xml");

adjust_dialog.center_sliders = func {
	var ns = adjust_dialog.namespace();
	if (ns != nil)
		ns.center();
}


# hide status line in screenshots
#
var status_restore = nil;
setlistener("/sim/signals/screenshot", func(n) {
	if (n.getBoolValue()) {
		status_restore = status_dialog.is_open();
		status_dialog.close();
	} elsif (status_restore) {
		status_dialog.open();
	}
});



# mouse walk --------------------------------------------------------------------------------------

var lastelev = nil;
var mouse = { savex: nil, savey: nil };
setlistener("/sim/startup/xsize", func(n) mouse.centerx = int(n.getValue() / 2), 1);
setlistener("/sim/startup/ysize", func(n) mouse.centery = int(n.getValue() / 2), 1);
setlistener("/sim/mouse/hide-cursor", func(n) mouse.hide = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/x", func(n) mouse.x = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/y", func(n) mouse.y = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/mode", func(n) mouse.mode = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/button[0]", func(n) mouse.lmb = n.getValue(), 1);
setlistener("/devices/status/mice/mouse/button[1]", func(n) {
	mouse.mmb = n.getValue();
	if (mouse.mode)
		return;
	if (mouse.mmb) {
		setprop("/controls/engines/engine/throttle", 0);
		controls.centerFlightControls();
		adjust_dialog.center_sliders();
		lastelev = getprop("/position/ground-elev-ft");
		mouse.savex = mouse.x;
		mouse.savey = mouse.y;
		gui.setCursor(mouse.centerx, mouse.centery, "none");
	} else {
		gui.setCursor(mouse.savex, mouse.savey, "pointer");
	}
}, 1);


mouse.loop = func {
	if (mouse.mode or !mouse.mmb)
		return settimer(mouse.loop, 0);

	var dx = mouse.x - mouse.centerx;
	var dy = -mouse.y + mouse.centery;
	if (!dx and !dy)
		return settimer(mouse.loop, 0);

	var speed = KbdShift.getValue() ? 1 : 0.1;
	var progress = 1.7;
	var powx = npow(dx, progress) * speed;
	var powy = npow(dy, progress) * speed;
	var option = mouse.lmb or gear_key_down;

	if (KbdCtrl.getValue()) {     # operation
		if (dx) {
			if (option)
				modelmgr.adjust("bearing", dx * 0.03, 1);
			else
				modelmgr.adjust("transversal", powx * 0.03, 1);
		}

		if (dy) {
			if (option)
				modelmgr.adjust("altitude", powy * 0.03, 1);
			else
				modelmgr.adjust("longitudinal", powy * 0.03, 1);
		}

	} else {                      # navigation
		var pos = geo.aircraft_position();
		var hdg = getprop("/orientation/heading-deg");
		var elev = getprop("/position/ground-elev-ft");
		var dalt = elev - lastelev;
		lastelev = elev;

		if (dx) {
			if (option)
				pos.apply_course_distance(hdg + 90, powx);
			else
				setprop("/orientation/heading-deg", hdg + dx * 0.2);
		}

		if (dy) {
			if (option)
				dalt += powy;
			else
				pos.apply_course_distance(hdg, powy);
		}
		setprop("/position/latitude-deg", pos.lat());
		setprop("/position/longitude-deg", pos.lon());
		setprop("/position/altitude-ft", getprop("/position/altitude-ft") + dalt);
	}

	gui.setCursor(mouse.centerx, mouse.centery);
	settimer(mouse.loop, 0);
}

mouse.loop();



# library stuff -----------------------------------------------------------------------------------

var ERAD = geo.ERAD;		# Earth radius (m)

var normdeg = geo.normdeg;
var npow = func(v, w) v == 0 ? 0 : math.exp(math.ln(abs(v)) * w) * (v < 0 ? -1 : 1);


var init_prop = func(prop, value) {
	if (prop.getValue() != nil)
		value = prop.getValue();

	prop.setDoubleValue(value);
	return value;
}


# binary search of string in sorted vector; returns index or -1 if not found
#
var search = func(list, which) {
	var left = 0;
	var right = size(list);
	var middle = nil;
	while (1) {
		middle = int((left + right) / 2);
		var c = cmp(list[middle], which);
		if (!c)
			return middle;
		elsif (left == middle)
			return -1;
		elsif (c > 0)
			right = middle;
		else
			left = middle;
	}
}


# scan all objects in subdir of $FG_ROOT. (Prefer *.xml files to *.osg files
# to *.ac files with the same basename.)
#
var scan_models = func(base) {
	var result = [];
	var root = getprop("/sim/fg-root");
	var list = directory(root ~ "/" ~ base);
	if (list == nil)
		return result;

	var ext = { ".ac": 1, ".osg": 2, ".xml": 3 }; # extension priorities
	var files = {};
	foreach (var d; list) {
		if (d[0] == `.` or d == "CVS")
			continue;
		if ((var stat = io.stat(root ~ "/" ~ base ~ "/" ~ d)) == nil)
			continue;
		if (stat[11] == "dir") {
			foreach (var s; scan_models(base ~ "/" ~ d))
				append(result, s);
			continue;
		}
		foreach (var e; keys(ext)) {
			if (substr(d, -size(e)) == e) {
				var basepath = base ~ "/" ~ substr(d, 0, size(d) - size(e));
				if (!contains(files, basepath) or ext[e] > ext[files[basepath]])
					files[basepath] = e;
				break;
			}
		}
	}
	foreach (var m; keys(files))
		append(result, m ~ files[m]);
	return result;
}



# -------------------------------------------------------------------------------------------------


# loop that generates the model flashing pulse
#
var clock = 0;
var clock_loop = func {
	clock = !clock;
	settimer(clock_loop, 0.3);
}
clock_loop();


# class that maintains one adjustable model property (see src/Model/modelmgr.cxx)
#
var ModelValue = {
	new : func(base, name, value) {
		var m = { parents: [ModelValue] };
		m.propN = base.getNode(name, 1);
		m.propN.setDoubleValue(value);
		base.getNode(name ~ "-prop", 1).setValue(m.propN.getPath());
		return m;
	},
	set : func(v) {
		me.propN.setDoubleValue(v);
	},
	get : func {
		me.propN.getValue();
	},
};


# class that maintains one scenery object (see src/Model/modelmgr.cxx)
#
var Model = {
	new : func(path, pos, data = nil) {
		var m = { parents: [Model] };
		m.pos = pos;
		m.path = path;
		m.selected = 1;
		m.visible = 1;
		m.flash_until = 0;
		m.loopid = 0;
		m.elapsedN = props.globals.getNode("/sim/time/elapsed-sec", 1);

		var models = props.globals.getNode("/models", 1);
		for (var i = 0; 1; i += 1) {
			if (models.getChild("model", i, 0) == nil) {
				m.node = models.getChild("model", i, 1);
				break;
			}
		}

		m.node.getNode("legend", 1).setValue("");
		if (data != nil and isa(data, props.Node))
			props.copy(data, m.node);		# import node

		var hdg = init_prop(m.node.getNode("heading-deg", 1), 0);
		var pitch = init_prop(m.node.getNode("pitch-deg", 1), 0);
		var roll = init_prop(m.node.getNode("roll-deg", 1), 0);

		m.node.getNode("path", 1).setValue(path);
		m.lat = ModelValue.new(m.node, "latitude-deg", pos.lat());
		m.lon = ModelValue.new(m.node, "longitude-deg", pos.lon());
		m.alt = ModelValue.new(m.node, "elevation-ft", pos.alt() * M2FT);
		m.hdg = ModelValue.new(m.node, "heading-deg", hdg);
		m.pitch = ModelValue.new(m.node, "pitch-deg", pitch);
		m.roll = ModelValue.new(m.node, "roll-deg", roll);
		m.node.getNode("load", 1).remove();
		return m;
	},
	remove : func {
		me.node.remove();
	},
	clone : func(path) {
		Model.new(path, geo.Coord.new(me.pos), me.node);
	},
	move : func(pos) {
		var v = me.visible;
		me.unhide();
		me.pos.set(pos);
		me.lat.set(me.pos.lat());
		me.lon.set(me.pos.lon());
		me.alt.set(me.pos.alt() * M2FT);
		v or me.hide();
	},
	raise : func (dist) {
		var v = me.visible;
		me.unhide();
		me.pos.set_alt(me.pos.alt() + dist);
		me.alt.set(me.pos.alt() * M2FT);
		v or me.hide();
	},
	apply_course_distance : func(course, dist) {
		me.pos.apply_course_distance(course, dist);
		me.lat.set(me.pos.lat());
		me.lon.set(me.pos.lon());
	},
	direct_distance_to : func(dest) {
		me.pos.direct_distance_to(dest);
	},
	flash : func(v) {
		me.loopid += 1;
		if (v) {
			me.flash_until = me.elapsedN.getValue() + 2;
			me._flash_(me.loopid);
		} else {
			me.unhide();
		}
	},
	_flash_ : func(id) {
		id == me.loopid or return;
		if (me.elapsedN.getValue() > me.flash_until)
			return me.unhide();
		elsif (clock)
			me.hide();
		else
			me.unhide();
		settimer(func { me._flash_(id) }, 0);
	},
	hide : func {
		me.visible or return;
		me.alt.set(me.alt.get() - ERAD);
		me.visible = 0;
	},
	unhide : func {
		me.visible and return;
		me.alt.set(me.alt.get() + ERAD);
		me.visible = 1;
	},
	get_data : func {
		var n = props.Node.new();
		props.copy(me.node, n);
		me.add_derived_data(n);
		return n;
	},
	add_derived_data : func(node) {
		node.removeChildren("latitude-deg-prop");
		node.removeChildren("longitude-deg-prop");
		node.removeChildren("elevation-ft-prop");
		node.removeChildren("heading-deg-prop");
		node.removeChildren("pitch-deg-prop");
		node.removeChildren("roll-deg-prop");

		var path = node.getNode("path").getValue();
		var lat = node.getNode("latitude-deg").getValue();
		var lon = node.getNode("longitude-deg").getValue();
		var elev = node.getNode("elevation-ft").getValue();
		var hdg = node.getNode("heading-deg").getValue();
		var legend = node.getNode("legend").getValue();
		var type = nil;
		var spec = "";

		if (path == "Aircraft/ufo-Bombable/Models/sign.ac") {
			type = "OBJECT_SIGN";
			if (legend == "")
				legend = "{@size=10,@material=RedSign}NO_CONTENTS_" ~ int(10000 * rand());

			foreach (var c; split('', legend))
				if (c != ' ')
					spec ~= c;
		} else {
			type = "OBJECT_SHARED";
			spec = path;
		}

		var elev_m = elev * FT2M;
		var stg_hdg = normdeg(360 - hdg);
		var stg_path = geo.tile_path(lat, lon);
		var abs_path = getprop("/sim/fg-root") ~ "/" ~ path;
		var obj_line = sprintf("%s %s %.8f %.8f %.4f %.1f", type, spec, lon, lat, elev_m, stg_hdg);

		node.getNode("absolute-path", 1).setValue(abs_path);
		node.getNode("legend", 1).setValue(legend);
		node.getNode("stg-path", 1).setValue(stg_path);
		node.getNode("stg-heading-deg", 1).setDoubleValue(stg_hdg);
		node.getNode("elevation-m", 1).setDoubleValue(elev_m);
		node.getNode("object-line", 1).setValue(obj_line);
		return node;
	},
};


var modelmgr = {
	init : func(path) {
		me.active = nil;
		me.models = [];
		me.legendN = props.globals.getNode("/sim/gui/dialogs/ufo-status/input", 1);
		me.legendN.setValue("");
		me.mouse_coord = geo.aircraft_position();
		me.import();
		me.marker = Model.new("Aircraft/ufo-Bombable/Models/marker.ac", geo.Coord.new().set_xyz(0, 0, 0));
		me.marker.hide();
		me.modelpath = path;
		if (me.active != nil)
			me.marker.move(me.active.pos);

		if (path != "Aircraft/ufo-Bombable/Models/cursor.ac")
			status_dialog.open();
	},
	click : func(mouse_coord) {
		if (gear_key_down)
			return teleport(mouse_coord, me.active);

		me.mouse_coord = mouse_coord;
		status_dialog.open();
		adjust_dialog.center_sliders();

		if (KbdAlt.getValue()) {	# move active object here (and other selected ones along with it)
			(me.active == nil) and return;
			var course = me.active.pos.course_to(me.mouse_coord);
			var distance = me.active.pos.distance_to(me.mouse_coord);
			foreach (var m; me.models) {
				m.pos.set_alt(me.mouse_coord.alt());
				m.selected and m.apply_course_distance(course, distance);
			}
			me.marker.move(me.active.pos);
			return;
		}

		if (!KbdShift.getValue())
			me.deselect_all();

		if (KbdCtrl.getValue()) {	# select existing object
			me.select();
		} else {			# add one new object
			me.active = Model.new(me.modelpath, mouse_coord, me.sticky_data());
			append(me.models, me.active);
			me.display_status(me.modelpath);
			me.marker.move(me.active.pos);

			if (KbdShift.getValue())
				foreach (var m; me.models)
					m.flash(m.selected);
		}
	},
	select : func() {
		if (!size(me.models)) {
			me.active = nil;
			me.marker.hide();
			return;
		}
		var min_dist = 10 * ERAD;

		forindex (var i; me.models) {
			var dist = me.models[i].direct_distance_to(me.mouse_coord);
			if (dist < min_dist) {
				min_dist = dist;
				me.active = me.models[i];
			}
		}
		me.active.selected = 1;
		me.marker.move(me.active.pos);
		var selected = [];
		foreach (var m; me.models) {
			m.flash(m.selected);
			if (m.selected)
				append(selected, m);
		}
		if (size(selected) == 2) {
			var dist = selected[0].direct_distance_to(selected[1].pos);
			screen.log.write(sprintf("%.3f m", dist));
		}

		me.display_status(me.modelpath = me.active.path);
	},
	selected_models : func {
		var models = [];
		foreach (var m; me.models)
			if (m.selected)
				append(models, m);
		return models;
	},
	deselect_all : func {
		foreach (var m; me.models)
			m.flash(m.selected = 0);
	},
	remove_selected : func {
		var models = [];
		foreach (var m; me.models) {
			if (m.selected)
				m.remove();
			else
				append(models, m);
		}
		me.models = models;
		me.select();
		me.display_status(me.modelpath);
	},
	set_modelpath : func(path) {
		me.modelpath = path;
		me.display_status(path);
	},
	update_legend : func {
		if (me.active != nil)
			me.active.node.getNode("legend", 1).setValue(me.legendN.getValue());
	},
	display_status : func(path) {
		var legend = me.active == nil ? "" : me.active.node.getNode("legend", 1).getValue();
		me.legendN.setValue(legend);
		setprop("/sim/model/ufo/status", "(" ~ size(me.models) ~ ")  " ~ path);
	},
	get_data : func {
		var n = props.Node.new();
		forindex (var i; me.models)
			props.copy(me.models[i].get_data(), n.getChild("model", i, 1));

		return n;
	},
	cycle : func(up) {
		var i = search(modellist, me.modelpath) + up;
		if (i < 0)
			i = size(modellist) - 1;
		elsif (i >= size(modellist))
			i = 0;

		me.set_modelpath(modellist[i]);

		var models = [];
		foreach (var m; me.models) {
			if (m.selected) {
				append(models, m.clone(modellist[i]));
				m.remove();
			} else {
				append(models, m);
			}
		}
		me.models = models;
	},
	sticky_data : func {
		var n = props.Node.new();
		if (me.active == nil)
			return n;

		var hdg = n.getNode("heading-deg", 1);
		var pitch = n.getNode("pitch-deg", 1);
		var roll = n.getNode("roll-deg", 1);
		if (getprop("/models/adjust/sticky-heading"))
			hdg.setDoubleValue(me.active.node.getNode("heading-deg").getValue());
		else
			hdg.setDoubleValue(0);

		if (getprop("/models/adjust/sticky-orientation")) {
			pitch.setDoubleValue(me.active.node.getNode("pitch-deg").getValue());
			roll.setDoubleValue(me.active.node.getNode("roll-deg").getValue());
		} else {
			pitch.setDoubleValue(0);
			roll.setDoubleValue(0);
		}
		return n;
	},
	reset_heading : func {
		foreach (var m; me.selected_models())
			m.hdg.set(0);
	},
	reset_orientation : func {
		foreach (var m; me.selected_models()) {
			m.pitch.set(0);
			m.roll.set(0);
		}
	},
	import : func {
		me.active = nil;
		var mandatory = ["path", "latitude-deg", "longitude-deg", "elevation-ft"];
		foreach (var m; props.globals.getNode("models", 1).getChildren("model")) {
			var ok = 1;
			foreach (var a; mandatory)
				if (m.getNode(a) == nil or m.getNode(a).getType() == "NONE")
					ok = 0;
			if (ok) {
				var tmp = props.Node.new({ legend:"", "heading-deg":0, "pitch-deg":0, "roll-deg":0 });
				props.copy(m, tmp);
				m.getParent().removeChild(m.getName(), m.getIndex());
				var c = geo.Coord.new().set_latlon(
						tmp.getNode("latitude-deg").getValue(),
						tmp.getNode("longitude-deg").getValue(),
						tmp.getNode("elevation-ft").getValue() * FT2M);
				append(me.models, me.active = Model.new(tmp.getNode("path").getValue(), c, tmp));
			}
		}
	},
	adjust : func(name, value, scale = 0) {
		if (!size(me.models) or me.active == nil)
			return;

		var ufo = geo.aircraft_position();
		var dist = scale ? ufo.distance_to(me.active.pos) * 0.05 : 1;
		if (name == "longitudinal") {
			var dir = ufo.course_to(me.active.pos);
			foreach (var m; me.selected_models())
				m.apply_course_distance(dir, value * dist);

		} elsif (name == "transversal") {
			var dir = ufo.course_to(me.active.pos) + 90;
			foreach (var m; me.selected_models())
				m.apply_course_distance(dir, value * dist);

		} elsif (name == "altitude") {
			foreach (var m; me.selected_models())
				m.raise(value * dist * 0.4);

		} elsif (name == "heading") {
			foreach (var m; me.selected_models())
				m.hdg.set(m.hdg.get() + value * 4);

		} elsif (name == "pitch") {
			foreach (var m; me.selected_models())
				m.pitch.set(m.pitch.get() + value * 6);

		} elsif (name == "roll") {
			foreach (var m; me.selected_models())
				m.roll.set(m.roll.get() + value * 6);

		} elsif (name == "bearing") {
			foreach (var m; me.selected_models()) {
				var course = me.active.pos.course_to(m.pos);
				var dist = me.active.pos.distance_to(m.pos);
				m.apply_course_distance(course, -dist);
				m.apply_course_distance(course + value * 4, dist);
				m.hdg.set(m.hdg.get() + value * 4);
			}
		}
		me.marker.move(me.active.pos);
	},
	toggle_marker : func {
		me.marker.visible ? me.marker.hide() : me.marker.unhide();
	},
	clone_selected : func {
		var clones = [];
		foreach (var m; me.selected_models()) {
			m.selected = 0;
			var c = m.clone(m.path);
			#c.selected = 1;
			append(clones, c);
			if (m == me.active)
				me.active = c;
		}
		foreach (var m; clones)
			append(me.models, m);
	},
};



var scan_dirs = func(csv) {
	var list = ["Aircraft/ufo-Bombable/Models/sign.ac", "Aircraft/ufo-Bombable/Models/cursor.ac"];
	foreach (var dir; split(",", csv))
		foreach (var m; scan_models(dir))
			append(list, m);

	return sort(list, cmp);
}



var print_ufo_data = func {
	print("\n\n------------------------------ UFO -------------------------------\n");

	var lat = getprop("/position/latitude-deg");
	var lon = getprop("/position/longitude-deg");
	var alt_ft = getprop("/position/altitude-ft");
	var elev_m = getprop("/position/ground-elev-m");
	var heading = getprop("/orientation/heading-deg");
	var agl_ft = alt_ft - elev_m * M2FT;

	printf("Latitude:     %.8f deg", lat);
	printf("Longitude:    %.8f deg", lon);
	printf("Altitude ASL: %.4f m (%.4f ft)", alt_ft * FT2M, alt_ft);
	printf("Altitude AGL: %.4f m (%.4f ft)", agl_ft * FT2M, agl_ft);
	printf("Heading:      %.1f deg", normdeg(heading));
	printf("Ground Elev:  %.4f m (%.4f ft)", elev_m, elev_m * M2FT);
	print();
	print("# " ~ geo.tile_path(lat, lon));
	printf("OBJECT_STATIC %.8f %.8f %.4f %.1f", lon, lat, elev_m, normdeg(360 - heading));
	print();

	var hdg = normdeg(heading + getprop("/sim/current-view/goal-pitch-offset-deg"));
	printf("http://maps.google.com/maps?ll=%.10f,%.10f&z=12&t=h\n", lat, lon);
	printf("$ fgfs --aircraft=ufo --lat=%.6f --lon=%.6f --altitude=%.2f --heading=%.1f\n",
			lat, lon, alt_ft, hdg);
}


var print_model_data = func(prop) {
	print("\n\n------------------------ Selected Object -------------------------\n");
	var elev = prop.getNode("elevation-ft").getValue();
	printf("Path:         %s", prop.getNode("path").getValue());
	printf("Latitude:     %.8f deg", prop.getNode("latitude-deg").getValue());
	printf("Longitude:    %.8f deg", prop.getNode("longitude-deg").getValue());
	printf("Altitude ASL: %.4f m (%.4f ft)", elev * FT2M, elev);
	printf("Heading:      %.1f deg", prop.getNode("heading-deg").getValue());
	printf("Pitch:        %.1f deg", prop.getNode("pitch-deg").getValue());
	printf("Roll:         %.1f deg", prop.getNode("roll-deg").getValue());
}


var teleport = func(target, lookat = nil) {
	setprop("/position/latitude-deg", target.lat());
	setprop("/position/longitude-deg", target.lon());
	setprop("/position/altitude-ft", target.alt() * M2FT + getprop("/position/altitude-agl-ft"));

	var hdg = props.globals.getNode("/orientation/heading-deg");
	if (lookat != nil)
		hdg.setDoubleValue(target.course_to(lookat.pos));
	else
		hdg.setDoubleValue(hdg.getValue() - getprop("/sim/current-view/heading-offset-deg"));
	view.resetView();
}



# interface functions -----------------------------------------------------------------------------


var vert_factor = 1;
var up = func(dir) {
	if (!dir)
		return vert_factor = 1;
	var alt = "position/altitude-ft";
	setprop(alt, getprop(alt) + 0.15 * vert_factor * dir);
	vert_factor += 0.25;
}


var print_data = func {
	var rule = "\n------------------------------------------------------------------\n";
	print("\n\n");
	print_ufo_data();

	var data = modelmgr.get_data();

	var selected = data.getChild("model", 0);
	if (selected == nil)
		return print(rule);

	print_model_data(selected);
	print(rule);

	# group all objects of a bucket
	var bucket = {};
	foreach (var m; data.getChildren("model")) {
		var stg = m.getNode("stg-path").getValue();
		var obj = m.getNode("object-line").getValue();
		if (contains(bucket, stg))
			append(bucket[stg], obj);
		else
			bucket[stg] = [obj];
	}
	foreach (var key; keys(bucket)) {
		print("\n# ", key);
		foreach (var obj; bucket[key])
			print(obj);
	}
	print(rule);
}


var export_data = func {
	var path = getprop("/sim/fg-home") ~ "/Export/ufo-model-export.xml";
	var args = props.Node.new({ filename : path });
	props.copy(modelmgr.get_data(), args.getNode("data/models", 1));
	if (fgcommand("savexml", args))
		print("model data exported to ", path);
}


var export_flightplan = func {
	var path = getprop("/sim/fg-home") ~ "/Export/ufo-flightplan-export.xml";
	var args = props.Node.new({ filename : path });
	var export = args.getNode("data/flightplan", 1);
	var waypoints = modelmgr.get_data().getChildren("model");
	if (!size(waypoints))
		return;
	forindex (var i; waypoints) {
		var from = waypoints[i];
		var to = export.getChild("wpt", i, 1);
		to.getNode("name", 1).setValue("#" ~ i);
		to.getNode("lat", 1).setDoubleValue(from.getNode("latitude-deg").getValue());
		to.getNode("lon", 1).setDoubleValue(from.getNode("longitude-deg").getValue());
		to.getNode("crossat", 1).setDoubleValue(from.getNode("elevation-ft").getValue());
		to.getNode("on-ground", 1).setBoolValue(1);
		to.getNode("ktas", 1).setDoubleValue(100);
	}
	export.getChild("wpt", i + 1, 1).getNode("name", 1).setValue("END");

	fgcommand("savexml", args);
	print("flightplan exported to ", path);
}


var file_selector = nil;

# called via l-key (load object from disk)
var file_select_model = func {
	if (file_selector == nil)
		file_selector = gui.FileSelector.new(fsel_callback,
				"Select 3D model file", "Load Model",
				["*.ac", "*.osg", "*.xml"], getprop("/sim/fg-root"));
	file_selector.open();
}

var fsel_callback = func(n) {
	var model = n.getValue();
	var root = string.normpath(getprop("/sim/fg-root")) ~ "/";
	if (substr(model, 0, size(root)) == root)
		model = substr(model, size(root));

	append(modellist, model);
	modellist = sort(modellist, cmp);
	modelmgr.set_modelpath(model);
}



# init --------------------------------------------------------------------------------------------

var KbdShift = props.globals.getNode("/devices/status/keyboard/shift");
var KbdCtrl = props.globals.getNode("/devices/status/keyboard/ctrl");
var KbdAlt = props.globals.getNode("/devices/status/keyboard/alt");

var modellist = scan_dirs(getprop("/source"));
modelmgr.init(getprop("/cursor"));

setlistener("/sim/signals/click", func {
	if (!mouse.mmb)
		modelmgr.click(geo.click_position());
});


