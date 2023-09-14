# A-10 Engines
# ------------
# Authors: David Bastien and Alexis Bory

# TODO: - Protect engine from overtemp, overpressure and stall
#       - motor @ IDLE for manual start
#       - Ignition effect if n2 > 10 && collector_tk != 0 && !ats_valve
#       - Take care of throttle cut OFF position

# ATS Valve : Air Turbine Start Valve.


var LeftEngine  = nil;
var RightEngine = nil;


var initialize = func {
	# Engines ("name", number)
	LeftEngine  = Engine.new( "Left Engine", 0);
	RightEngine  = Engine.new( "Right Engine", 1);
}


var update_loop = func( n ) {

	var e       = LeftEngine;
	var other_e = RightEngine;
	if ( n ) {
		e       = RightEngine;
		other_e = LeftEngine;
	} 

	var eng_serviceable = e.get_serviceable();
	var eng_switch_pos = e.get_switch_pos();
	var eng_throttle_pos = e.get_throttle_pos();
	var eng_n1 = e.get_n1();
	var eng_n2 = e.get_n2();
	var eng_n1_yasim = e.get_n1_yasim();
	var eng_n2_yasim = e.get_n2_yasim();
	e.eng_n1_goal = 0;
	e.eng_n2_goal = 0;
	var ats_valve = e.get_ats_valve();
	var ats_valve_oth = other_e.get_ats_valve();
	var eng_collector_tank = e.get_collector_tk();
	var eng_out_of_fuel = 1;
	var time_now = getprop("sim/time/elapsed-sec");


	if ( e.get_cutoff() ) {
		e.set_throttle_pos( 0 );
		eng_throttle_pos = 0;
	} elsif ( eng_throttle_pos < 0.03 ) {
		e.set_throttle_pos( 0.03 );
		eng_throttle_pos = 0.03;
	}
	e.set_alt_throttle_pos( eng_throttle_pos );


	# Hydraulic pressure: normal pressure: 2800-3350 psi
	var hydr_press = 0;
	if ( e.get_hydraulic_pump_serviceable() and e.get_hyd_res() > 40) {
		# TODO: hyd_res : hydraulic-resistance ???
		# Not computed yet, value fixed a 100 in the -set file.
		if ( eng_n2 >= 56 ) {
			hydr_press = ( 10.78431 * eng_n2 ) + 2250;
		} else {
			hydr_press = 50 * eng_n2;
		}
	}
	e.set_hyd_psi(hydr_press);


	# Aux LDG extend accumulator pressurised by right hydraulic circuit. 
	if ( e.get_index() and getprop("/systems/A-10-hydraulics/aux-lg-ext-accumulator") < 900 and e.get_hyd_psi() > 900 )
		setprop("/systems/A-10-hydraulics/aux-lg-ext-accumulator", hydr_press);


	# Check IGN / MOTOR switch.
	if ( eng_switch_pos == 2 ) {
		# IGN position. 
		e.set_switch_pos(1); # spring-loaded => back to NORM position
		# Start a ignition cycle of 30 seconds
		if ( e.eng_ignit_time == 0  and eng_throttle_pos >= 0.03 ) {
			e.ign_selected = 1;
			e.eng_ignit_time = time_now;
			e.set_ignitors_0(1);
			e.set_ignitors_1(1);
		}
	} elsif ( eng_switch_pos == 1) {
		# NORM position
		if (
			getprop("systems/bleed-air/psi") > 50
			and eng_throttle_pos >= 0.03 and eng_throttle_pos <= 0.06
			and eng_n2 < 56
			and electrical.AC_ESSEN_bus_volts > 23
			and ! ats_valve
			and ! ats_valve_oth
		) {
			e.set_ats_valve(1);
			ats_valve = 1;
		}
		# Start ignition (30 sec max).
		if ( ats_valve and eng_n2 >= 10 and eng_n2 < 56 and e.eng_ignit_time == 0 ) {
			e.eng_ignit_time = time_now;
			e.set_ignitors_0(1);
			e.set_ignitors_1(1);
		}
		# Start ATS valve timer (10 sec max).
		if ( ats_valve and eng_n2 >= 56 and e.ats_valve_time == 0 ) {
			e.ats_valve_time = time_now;
		}
	} else {
		# MOTOR position
		if (
			getprop("systems/bleed-air/psi") > 50
			and eng_throttle_pos < 0.03
			and electrical.AC_ESSEN_bus_volts > 23
			and ! ats_valve
			and ! ats_valve_oth
		) {
			e.set_ats_valve(1);
			ats_valve = 1;
		}
	}

	# Close ATS valve
	if ( ats_valve ) {
		if (
			eng_throttle_pos > 0.06
			or ( eng_throttle_pos < 0.03 and eng_switch_pos != 0 )
			or ( e.ats_valve_time != 0 and ( time_now > (e.ats_valve_time + 10) ) )
		) {
			e.set_ats_valve(0);
			e.ats_valve_time = 0;
			ats_valve = 0;
		}
	}

	# Stop ignition
	if ( e.get_ignitors_0() or e.get_ignitors_1() ) {
		if (
			( time_now > ( e.eng_ignit_time + 30 ) and ( e.ign_selected or  eng_n2 >= 56 ) )
			or eng_throttle_pos < 0.03
		) {
			e.eng_ignit_time = 0;
			e.set_ignitors_0(0);
			e.set_ignitors_1(0);
		}
	}

	# Simulate engine core speed
	if ( eng_serviceable ) {
		if (
			! ats_valve
			and eng_throttle_pos >= 0.03
			and eng_collector_tank > 0
			and ! e.get_out_of_fuel()
		) {
			# Engine running
			eng_n1 = eng_n1_yasim;
			eng_n2 = eng_n2_yasim;
			eng_out_of_fuel = 0;
		} elsif (
			ats_valve
			and ( e.ats_valve_time != 0 or e.get_ignitors_0_volts() > 23 or e.get_ignitors_1_volts() > 23 )
			and eng_collector_tank > 0
		) {
			# NORM startup
			e.eng_n1_goal = eng_n1_yasim;
			e.eng_n2_goal = eng_n2_yasim; # should be near 56% rpm
			eng_out_of_fuel = 0;
		} elsif ( ats_valve ) {
			# MOTOR
			e.eng_n1_goal = 8;
			e.eng_n2_goal = 16;
		}
	}
	if ( eng_n2 != eng_n2_yasim ) {
		# Calculate the core engine speed
		var gain = 1.72;
		var tm = 0.2;
		var thau = 1.2;
		var delta_n1 = e.eng_n1_goal - eng_n1;
		eng_n1 += ( delta_n1 * gain * math.exp( -tm / A10.UPDATE_PERIOD ) ) / ( 1 + ( thau / A10.UPDATE_PERIOD ) );
		if ( eng_n1 < 0 ) { eng_n1 = 0; }
		var delta_n2 = e.eng_n2_goal - eng_n2;
		eng_n2 += ( delta_n2 * gain * math.exp( -tm / A10.UPDATE_PERIOD ) ) / ( 1 + ( thau / A10.UPDATE_PERIOD ) );
		if ( eng_n2 < 0 ) { eng_n2 = 0; }
	}

	e.set_out_of_fuel( eng_out_of_fuel );
	e.set_n1( eng_n1 );
	e.set_n2( eng_n2 );
	
}



# Controls ################

var eng_oper_switch_move = func(n, s) {
	# 3 positions 'ENG OPER' switch.
	var e = LeftEngine;
	if ( n ) { e = RightEngine; }
	var switch_pos = e.get_switch_pos();
	if ( switch_pos < 2 and s == 1 ) {
		switch_pos += 1;
	} elsif ( s == 0 and switch_pos > 0 ) {
		switch_pos -= 1;
	}
	e.set_switch_pos(switch_pos);
}

var throttle_cutoff_mov = func(n) {
	# Throttle from OFF to IDLE
	var e = LeftEngine;
	if ( n ) { e = RightEngine; }
	if ( e.get_cutoff() ) {
		e.set_cutoff( 0 );
		e.set_throttle_pos( 0.03 );
	} elsif ( e.get_throttle_pos() < 0.06 ) {
		e.set_cutoff(1);
		e.set_throttle_pos( 0 );
	}
}

var eng_autostart = func() {
	# Fast engines autostart.
	print("Launch autostart engines sequence.");
	setprop("controls/electric/engine[0]/generator", 1);
	setprop("controls/electric/engine[1]/generator", 1);
	LeftEngine.set_cutoff( 0 );
	LeftEngine.set_throttle_pos( 0.03 );
	RightEngine.set_cutoff( 0 );
	RightEngine.set_throttle_pos( 0.03 );
	LeftEngine.set_collector_tk( 1.519 );
	RightEngine.set_collector_tk( 1.519 );
	LeftEngine.set_out_of_fuel( 0 );
	RightEngine.set_out_of_fuel( 0 );
}




# Classes ################

# Engine
Engine = {
	new : func (name, number) {
		var obj = { parents : [Engine],
			eng_n1_goal    : 0,
			eng_n2_goal    : 0,
			eng_ignit_time : 0,
			ats_valve_time : 0,
			ign_selected   : 0,
		};
		obj.prop               = props.globals.getNode("engines").getChild("engine", number , 1);
		obj.name               = obj.prop.getNode("name", 1);
		obj.prop.getChild("name", 0, 1).setValue(name);
		obj.n1_yasim           = obj.prop.getNode("n1", 1);
		obj.n2_yasim           = obj.prop.getNode("n2", 1);
		obj.out_of_fuel        = obj.prop.getNode("out-of-fuel", 1);
		obj.fuel_flow_gph      = obj.prop.getNode("fuel-flow-gph", 1);
		obj.fuel_flow_pph      = obj.prop.getNode("fuel-flow-pph", 1);
		obj.fuel_consumed_lbs  = obj.prop.getNode("fuel-consumed-lbs", 1);
		obj.collector_tk       = obj.prop.getNode("collector-tank", 1);

		obj.control_prop       = props.globals.getNode("controls/engines").getChild("engine", number , 1);
		obj.throttle_pos       = obj.control_prop.getNode("throttle", 1);
		obj.cutoff             = obj.control_prop.getNode("cutoff", 1);
		obj.control_fault_prop = obj.control_prop.getNode("faults", 1);
		obj.ignitors_0         = obj.control_prop.getNode("engines-ignitors[0]", 1);
		obj.ignitors_1         = obj.control_prop.getNode("engines-ignitors[1]", 1);
		obj.control_prop.getChild("engines-ignitors", 0, 1).setBoolValue(0);
		obj.control_prop.getChild("engines-ignitors", 1, 1).setBoolValue(0);
		obj.serviceable        = obj.control_fault_prop.getNode("serviceable", 1);
		obj.hydraulic_pump_serviceable = obj.control_fault_prop.getNode("hydraulic-pump-serviceable", 1);

		obj.alt_prop           = props.globals.getNode("sim/model/A-10/engines").getChild("engine", number , 1);
		obj.n1                 = obj.alt_prop.getNode("n1", 1);
		obj.n2                 = obj.alt_prop.getNode("n2", 1);

		obj.alt_control_prop   = props.globals.getNode("sim/model/A-10/controls/engines").getChild("engine", number , 1);
		obj.switch_pos         = obj.alt_control_prop.getNode("starter-switch-position", 1);
		obj.alt_throttle_pos   = obj.alt_control_prop.getNode("throttle", 1);

		obj.elec_outputs       = props.globals.getNode("systems/electrical/outputs").getChild("engine", number , 1);
		obj.ignitors_0_volts   = obj.elec_outputs.getNode("engines-ignitors[0]", 1);
		obj.ignitors_1_volts   = obj.elec_outputs.getNode("engines-ignitors[1]", 1);

		obj.ats_valve         = props.globals.getNode("systems/bleed-air").getChild("ats-valve", number , 1);
		obj.hyd_res           = props.globals.getNode("systems/A-10-hydraulics").getChild("hyd-res", number ,1);
		obj.hyd_psi           = props.globals.getNode("systems/A-10-hydraulics").getChild("hyd-psi", number ,1);
	
		append(Engine.list, obj);
		return obj;
	},

	get_name : func () {
		return me.name.getValue();
	},
	get_index : func () {
		return me.prop.getIndex();
	},
	get_n1_yasim : func () {
		return me.n1_yasim.getValue();
	},
	get_n2_yasim : func () {
		return me.n2_yasim.getValue();
	},
	get_out_of_fuel : func () {
		return me.out_of_fuel.getBoolValue();
	},
	set_out_of_fuel : func (n) {
		me.out_of_fuel.setBoolValue(n);
	},
	get_fuel_flow_gph : func () {
		return me.fuel_flow_gph.getValue();
	},
	set_fuel_flow_pph : func (n) {
		me.fuel_flow_pph.setValue(n);
	},
	get_fuel_consumed_lbs : func () {
		return me.fuel_consumed_lbs.getValue();
	},
	set_fuel_consumed_lbs : func (n) {
		me.fuel_consumed_lbs.setValue(n);
	},
	get_collector_tk : func () {
		return me.collector_tk.getValue();
	},
	set_collector_tk : func (n) {
		me.collector_tk.setValue(n);
	},

	get_throttle_pos : func () {
		return me.throttle_pos.getValue();
	},
	set_throttle_pos : func (n) {
		me.throttle_pos.setValue(n);
	},
	get_cutoff : func () {
		return me.cutoff.getBoolValue();
	},
	set_cutoff : func (n) {
		me.cutoff.setBoolValue(n);
	},
	get_ignitors_0 : func () {
		return me.ignitors_0.getBoolValue();
	},
	set_ignitors_0 : func (n) {
		me.ignitors_0.setBoolValue(n);
	},
	get_ignitors_1 : func () {
		return me.ignitors_1.getBoolValue();
	},
	set_ignitors_1 : func (n) {
		me.ignitors_1.setValue(n);
	},
	get_serviceable : func () {
		return me.serviceable.getBoolValue();
	},
	get_hydraulic_pump_serviceable : func () {
		return me.hydraulic_pump_serviceable.getBoolValue();
	},

	get_n1 : func () {
		return me.n1.getValue();
	},
	set_n1 : func (n) {
		me.n1.setValue(n);
	},
	get_n2 : func () {
		return me.n2.getValue();
	},
	set_n2 : func (n) {
		me.n2.setValue(n);
	},

	get_switch_pos : func () {
		return me.switch_pos.getValue();
	},
	set_switch_pos : func (n) {
		me.switch_pos.setValue(n);
	},
	get_alt_throttle_pos : func () {
		return me.alt_throttle_pos.getValue();
	},
	set_alt_throttle_pos : func (n) {
		me.alt_throttle_pos.setValue(n);
	},

	get_ignitors_0_volts : func () {
		return me.ignitors_0_volts.getValue();
	},
	get_ignitors_1_volts : func () {
		return me.ignitors_1_volts.getValue();
	},

	get_ats_valve : func () {
		return me.ats_valve.getBoolValue();
	},
	set_ats_valve : func (n) {
		me.ats_valve.setBoolValue(n);
	},
	get_hyd_res : func () {
		me.hyd_res.getValue();
	},
	get_hyd_psi : func () {
		return me.hyd_psi.getValue();
	},
	set_hyd_psi : func (n) {
		me.hyd_psi.setValue(n);
	},

	list : [],
};
