
sin = func(a) { math.sin(a * math.pi / 180.0) }
cos = func(a) { math.cos(a * math.pi / 180.0) }

dynamic_view.register(func {
	me.default_plane();
	me.heading_offset = -15 * sin(me.roll) * cos(me.pitch);
});

aircraft.data.add("/sim/model/camel/extra-details");



