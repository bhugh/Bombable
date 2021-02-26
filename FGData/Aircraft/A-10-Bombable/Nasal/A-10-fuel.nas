# A-10 Fuel System
# ----------------
# Authors: David Bastien and Alexis Bory

# All values in US Gallons, unless specified.
# ATS Valve : Air Turbine Start Valve.

# A-10 fuel system operation logic:
# 2 wing tanks (left and right), 2 fuselage tanks (left main-aft and right
# main-forward)
# Up to 3 external tanks (2 wings and 1 fuselage).
# Normally the left wing and left main tanks feeds the left engine and the APU,
# the right wing and right main tanks feeds the right engine. The two feed lines
# could be interconnected by opening the cross feed valve.
# The wing boost pumps will supply the respective engine until the wing tanks
# are empty, at which time the wing boost pumps will automatically shut off.
# then supply the respective engine with the remainder fuel in the airplane.

# In case of a wing tank boost pump failure, the wing tank will gravity feed
# its respective main tank if this main tank fuel level is be below 600 lbs.
# Check valves prevent reverse fuel flow from the main tank to the wing tank.

# In the event of a main tank boost pump failure, the affected engine will
# suction-feed from the affected tank for all power setting up to an altitude of
# nearly 10,000 feet.

# Unequal fuel level between right main and left main tank (imbalance greater
# than 750 lbs) will cause center of gravity shift that may exceed allowable
# limits. In this case, a valve named "tank gate" can link the two main tanks.

# Fuel from the external tanks is transfered to the main or wing tanks by
# pressure from the bleed air system. Wing tanks can be topped when the fuel
# level is below 1590 lbs.
# Main tanks can be topped when the fuel level is below 3034 lbs.
# The cycling is repeated until fuel is depleted from the external wing tanks
# first, and external fuselage tank secondly.

# For negative G flight, collector tanks will supply the engine with sufficient
# fuel for 10 seconds operation at MAX power.

# TODO: - External tanks:
#       a) First empty Wing Externals, then Fuse External, then Wings.
#       b) Externals switches supply bleed air instead of boost pumps.
#		c) transfer bleed air is still supplied when main tanks low level
#		switches are actuated even if Ext tanks switch are OFF. 
#       - APU line branchs itself between Left Fire Valve and Left Cross Feed.

var TankGateValve  = nil;
var CrossFeedValve = nil;
var APU_FireValve  = nil;
var Left_FireValve = nil;
var Right_FireValve= nil;
var Left_Wing      = nil;
var Left_Main      = nil;
var Right_Main     = nil;
var DC_boost_pump  = nil;
var Right_Wing     = nil;
var Left_External  = nil;
var Fuse_External  = nil;
var Right_External = nil;
var L_DC_ok        = nil;
var DC_ESSEN_ok    = nil;
var counter        = 0;
var FuelFreeze     = props.globals.getNode("sim/freeze/fuel");
var AI_Enabled     = props.globals.getNode("sim/ai/enabled");
var AI_Models      = props.globals.getNode("ai/models");
var Pilot_G        = props.globals.getNode("accelerations/pilot-g");
var Pitch_Deg      = props.globals.getNode("orientation/pitch-deg");
var EnvPressInhg   = props.globals.getNode("environment/pressure-inhg", 1);
var XAccell_Fpss   = props.globals.getNode("accelerations/pilot/x-accel-fps_sec");
var DoorLock       = props.globals.getNode("systems/refuel/door-lock");
var ReceiverLever  = props.globals.getNode("systems/refuel/receiver-lever");
var RefuelServ     = props.globals.getNode("systems/refuel/serviceable");
var RefuelState    = props.globals.getNode("systems/refuel/state");
var HydPsi         = props.globals.getNode("systems/A-10-hydraulics/hyd-psi[1]", 1);
var FuelDspSel     = props.globals.getNode("sim/model/A-10/controls/fuel/fuel-dsp-sel", 1);
var FuelGaugeTest  = props.globals.getNode("sim/model/A-10/controls/fuel/fuel-test-ind", 1);
var FuelDiffLbs    = props.globals.getNode("sim/model/A-10/consumables/fuel/diff-lbs", 1);
var DspLeft        = props.globals.getNode("sim/model/A-10/consumables/fuel/fuel-dsp-left", 1);
var DspRight       = props.globals.getNode("sim/model/A-10/consumables/fuel/fuel-dsp-right", 1);
var DspDrum        = props.globals.getNode("sim/model/A-10/consumables/fuel/fuel-dsp-drum", 1);
var APU_Switch     = props.globals.getNode("controls/APU/off-start-switch");
var DC_Boost_Serv  = props.globals.getNode("controls/fuel/tank[1]/DC-boost-pump-serviceable");
var APU_OutofFuel  = props.globals.getNode("sim/model/A-10/systems/apu/out-of-fuel", 1);
var APU_FuelCons   = props.globals.getNode("sim/model/A-10/systems/apu/fuel-consumed-lbs", 1);
var SysFuelInit    = props.globals.initNode("systems/A-10-fuel/initialized", 0, "BOOL");
var APU_Collector  = props.globals.getNode("systems/A-10-fuel/apu-collector-tank", 1);
var LFeedLinePress = props.globals.getNode("systems/A-10-fuel/feed-line-press[0]", 1);
var RFeedLinePress = props.globals.getNode("systems/A-10-fuel/feed-line-press[1]", 1);
var TotalFuelGals  = props.globals.getNode("consumables/fuel/total-fuel-gals", 1);
var TotalFuelLbs   = props.globals.getNode("consumables/fuel/total-fuel-lbs", 1);
var FuelGaugeVolts = props.globals.getNode("systems/electrical/outputs/fuel-gauge-sel", 1);


var init = func {	
	if ( ! SysFuelInit.getBoolValue() ) {
		# Don't do it twice. ie: case of fgcommand("reinit"). 
		fuel.update = func {}; # Kill $FG_ROOT/Nasal/fuel.nas loop.
		# Valves ("name", "property", intitial status):
		TankGateValve   = Valve.new("systems/A-10-fuel/tank-gate-valve", 0);
		CrossFeedValve  = Valve.new("systems/A-10-fuel/cross-feed-valve", 0);
		APU_FireValve   = Valve.new("systems/A-10-fuel/eng-valve-apu-fire", 1);
		Left_FireValve  = Valve.new("systems/A-10-fuel/eng-valve-left-fire", 1);
		Right_FireValve = Valve.new("systems/A-10-fuel/eng-valve-right-fire", 1);
		# Tanks ("name", number, type (1 = internal), selected, control_fill_dis, fill_valve, density):
		Left_Wing       = Tank.new("Left Wing",           0, 1, 1, 0, 1, 6.4);
		Left_Main       = Tank.new("Left Main (Aft)",     1, 1, 1, 0, 1, 6.4);
		Right_Main      = Tank.new("Right Main (Fwd)",    2, 1, 1, 0, 1, 6.4);
		Right_Wing      = Tank.new("Right Wing",          3, 1, 1, 0, 1, 6.4);
		Left_External   = Tank.new("Left Wing External",  4, 0, 1, 0, 1, 6.4);
		Fuse_External   = Tank.new("Fuselage External",   5, 0, 1, 0, 1, 6.4);
		Right_External  = Tank.new("Right Wing External", 6, 0, 1, 0, 1, 6.4);
		DC_boost_pump   = Left_Main.prop.getNode("DC-boost-pump");
		foreach ( var e; A10engines.Engine.list ) {	e.set_out_of_fuel(1) }
		APU_OutofFuel.setBoolValue(1);
		SysFuelInit.setBoolValue(1);
	}
}


var update_loop = func {

	if ( FuelFreeze.getBoolValue() ) { return }

	var fuel_flow_gph           = 0;
	var PPG                     = Left_Wing.get_ppg();
	var gal_total               = 0;
	var gal_level               = 0;
	var lbs_total               = 0;
	var lbs_level               = 0;
	var fuel_flow_rate          = 0.896057 * A10.UPDATE_PERIOD; # 20000pph
	var aa_refuel_flow          = 0;
	var tk_gate_trans           = 0;      # gals
	var collector_tank_diff     = [0, 0]; # gals
	var left_wing_tank          = Left_Wing.get_level_lbs();
	var left_main_tank          = Left_Main.get_level_lbs();
	var right_main_tank         = Right_Main.get_level_lbs();
	var right_wing_tank         = Right_Wing.get_level_lbs();
	var fuel_dsp_sel            = FuelDspSel.getValue();
	var apu_collector_tank      = APU_Collector.getValue();
	var apu_collector_tank_diff = 0;
	var int_tanks_filled        = 0;
	var ext_tanks_filled        = 0;
	L_DC_ok                     = 0;
	DC_ESSEN_ok                 = 0;
	var ai_enabled              = AI_Enabled.getBoolValue();
	var env_press_inhg          = EnvPressInhg.getValue();

	if ( electrical.L_DC_bus_volts >= 20 )     { L_DC_ok = 1 }
	if ( electrical.DC_ESSEN_bus_volts >= 20 ) { DC_ESSEN_ok = 1 }


	# Feed lines pressure after cross feed and fire valves, should be between 5
	# and 7 psi.
	# (left engine, right engine, APU)
	var feed_line_pressure  = [0, 0, 0];
	# Feed lines pressure before the cross feed valve.
	# (left wing/main tanks, right wing/main tanks)
	var feed_line_pressure_bf = [0, 0];

	check_DC_pump();

	if ( Pilot_G.getValue() > 0 ) {
		if ( DC_boost_pump.getBoolValue() ) {
			feed_line_pressure_bf[0] = electrical.DC_ESSEN_bus_volts / 4.6;
		} elsif ( Left_Wing.get_boost_pump() or Left_Main.get_boost_pump() ) {
			feed_line_pressure_bf[0] = electrical.L_AC_bus_volts / 4.6;
		}
		if ( Right_Main.get_boost_pump() or Right_Wing.get_boost_pump() ) {
			feed_line_pressure_bf[1] = electrical.R_AC_bus_volts / 4.6;
		}
		# Engine suction feed, up to 10,000ft, all power settings, SL pressure = 29.92.
		feed_line_pressure[0] = ( A10engines.LeftEngine.get_n2() * env_press_inhg * 0.0010215 ) + 3.7823;
		feed_line_pressure[1] = ( A10engines.RightEngine.get_n2() * env_press_inhg * 0.0010215 ) + 3.7823;
	}

	
	if ( CrossFeedValve.is_open() ) {
		# Equalize feed-lines.
		if ( feed_line_pressure_bf[0] > 5 ) {
			feed_line_pressure[0] = feed_line_pressure_bf[0];
			feed_line_pressure[1] = feed_line_pressure_bf[0];
		} elsif ( feed_line_pressure_bf[1] > 5 ) {
			feed_line_pressure[0] = feed_line_pressure_bf[1];
			feed_line_pressure[1] = feed_line_pressure_bf[1];
		} else {
			if ( feed_line_pressure[0] > feed_line_pressure[1] ) {
				feed_line_pressure_bf[0] = feed_line_pressure[0];
				feed_line_pressure_bf[1] = feed_line_pressure[0];
			} else {
				feed_line_pressure_bf[0] = feed_line_pressure[1];
				feed_line_pressure_bf[1] = feed_line_pressure[1];
			}
			if ( left_main_tank < 10 ) { feed_line_pressure_bf[0] = 0 }
			if ( right_main_tank < 10 ) { feed_line_pressure_bf[1] = 0 }
			if ( feed_line_pressure_bf[0] == 0 and feed_line_pressure_bf[1] == 0 ) {
				feed_line_pressure[0] = 0;
				feed_line_pressure[1] = 0;
			}
		}
	} else {
		if ( feed_line_pressure_bf[0] > 5 ) {
			feed_line_pressure[0] = feed_line_pressure_bf[0];
		} else {
			if ( left_main_tank < 10 ) { feed_line_pressure[0] = 0 }
			feed_line_pressure_bf[0] = feed_line_pressure[0];
		}
		if ( feed_line_pressure_bf[1] > 5 ) {
			feed_line_pressure[1] = feed_line_pressure_bf[1];
		} else {
			if ( right_main_tank < 10 ) { feed_line_pressure[1] = 0 }
			feed_line_pressure_bf[1] = feed_line_pressure[1];
		}
	}
	feed_line_pressure[2] = feed_line_pressure[0];
	if ( ! APU_FireValve.is_open() ) { feed_line_pressure[2] = 0 }
	if ( ! Left_FireValve.is_open() ) { feed_line_pressure[0] = 0 }
	if ( ! Right_FireValve.is_open() ) { feed_line_pressure[1] = 0 }

	LFeedLinePress.setValue(feed_line_pressure[0]);
	RFeedLinePress.setValue(feed_line_pressure[1]);


	if ( feed_line_pressure[2] > 5 ) {
		apu_collector_tank_diff = 0.217 - apu_collector_tank;
		if ( apu_collector_tank_diff > 0 ) {
			apu_collector_tank += apu_collector_tank_diff
		} else {
			apu_collector_tank_diff = 0
		}
	}

	# substract fuel consumed by the APU
	var apu_outoffuel = 0;
	apu_collector_tank -= APU_FuelCons.getValue() / PPG;
	APU_FuelCons.setValue(0);
	if ( apu_collector_tank <= 0 ) {
		apu_collector_tank = 0;
		apu_outoffuel = 1;
	}
	APU_Collector.setValue(apu_collector_tank);
	APU_OutofFuel.setBoolValue(apu_outoffuel);


	# Updates engines collectors. 
	foreach ( var e; A10engines.Engine.list ) {
		var i = e.get_index();
		var collector = e.get_collector_tk();
		fuel_flow_gph = e.get_fuel_flow_gph();
		fuel_flow_gph = fuel_flow_gph * (6.72 / PPG); # Jet-4 from YASim Jet-A
		if ( e.get_alt_throttle_pos() >= 0.03 and e.get_n2() >= 10 ) {
			# Feed fuel collectors:
			# Capacity => 1.519 gallons => about 10 sec @ max throttle (3500pph)
			if ( feed_line_pressure[i] > 5 ) {
				collector_tank_diff[i] = 1.519 - collector;
				if ( collector_tank_diff[i] > 0 ) {
					collector += collector_tank_diff[i]
				} else {
					collector_tank_diff[i] = 0
				}
			}
			collector -= e.get_fuel_consumed_lbs()/PPG;
			e.set_fuel_consumed_lbs(0);
		} else {
			fuel_flow_gph = 0
		}
		# Jet-4 from YASim Jet-A for engine gauges display.
		e.set_fuel_flow_pph( fuel_flow_gph * 6.72 );
		if ( e.get_ats_valve() and e.get_n2() < 56 and e.get_n2() >= 10 ) {
			# Engines motoring. Requires 30 seconds to empty the collector tank.
			collector -= 0.0506 * A10.UPDATE_PERIOD
		}
		if ( collector < 0 ) { collector = 0 }
		e.set_collector_tk( collector );
	}



	# Add fuel consumed by the APU
	collector_tank_diff[0] = collector_tank_diff[0] + apu_collector_tank_diff;

	# Divide equally the fuel consumed if cross feed valve is open.
	if ( CrossFeedValve.is_open() ) {
		if ( feed_line_pressure_bf[0] > 5 and feed_line_pressure_bf[1] > 5 ) {
			collector_tank_diff[0] = ( collector_tank_diff[0] + collector_tank_diff[1] ) / 2;
			collector_tank_diff[1] = collector_tank_diff[0];
		} elsif ( feed_line_pressure_bf[0] > 5 and feed_line_pressure_bf[1] < 5 ) {
			collector_tank_diff[0] += collector_tank_diff[1]
		} else {
			collector_tank_diff[1] += collector_tank_diff[0]
		}
	}

	# Count number of tanks ready to be refueled
	foreach (var t; Tank.list) {
		if ( t.get_fill_valve() ) {
			if ( t.get_type() ) {
				int_tanks_filled += 1
			} else {
				ext_tanks_filled += 1
			}
		}
	}

	# Air to Air refueling
	if ( ai_enabled and DoorLock.getBoolValue() ) {
		var r_state = RefuelState.getValue();
		if ( r_state == 1 or r_state == 2 ) {
			if ( int_tanks_filled > 0  or ext_tanks_filled > 0 ) {
				var TankerList = AI_Models.getChildren("tanker");
				var MultiplayerList = AI_Models.getChildren("multiplayer");
				if ( TankerList != nil ) {
					aa_refuel_flow = aar_fuel_flow( TankerList )
				} elsif ( MultiplayerList != nil ) {
					aa_refuel_flow = aar_fuel_flow( MultiplayerList )
				}
			}
			if ( r_state == 1 and aa_refuel_flow > 0 ) {
				RefuelState.setValue(2)
			} elsif ( r_state == 2 and aa_refuel_flow == 0 ) {
				RefuelState.setValue(3)
			}
		}
	}

	# Update tanks fuel level.
	foreach (var t; Tank.list) {
		var j = t.get_index();
		gal_level = t.get_level();

		if ( counter == 2 ) { check_fill_valve(t) }	

		if ( j == 0 ) {
			if ( t.get_boost_pump() and ( feed_line_pressure_bf[0] > 5 ) ) {
				gal_level -= collector_tank_diff[0]
			}
			if ( Left_Wing.get_transfering() ) {
				gal_level -= fuel_flow_rate
			}

		} elsif ( j == 1 ) {
			# In case of main tank boost pump failure, engine could self feed if
			# feed line pressure is enough (=> collector_tank_diff > 0).
			if (
				feed_line_pressure_bf[0] > 5 and t.get_boost_pump()
				or DC_boost_pump.getBoolValue()
				or collector_tank_diff[0] > 0 and ! Left_Wing.get_boost_pump()
			) {
				gal_level -= collector_tank_diff[0]
			}
			if ( Left_Wing.get_transfering() ) {
				gal_level += fuel_flow_rate
			}
			if ( TankGateValve.is_open() ) {
				# Fuel flow between the 2 main tanks is:
				# - proportionnal to the pitch of the airplane
				# - proportionnal to the acceleration on the longitudinal axis
				# - proportionnal the difference level between this 2 tanks.
				var pitch_rad = Pitch_Deg.getValue() * D2R;
				var accel_fps = ( XAccell_Fpss.getValue() + 0.5 ) * D2R;
				var pounded_aft = gal_level * ( 1 - math.sin(pitch_rad) ) * ( 1 - math.sin(accel_fps) );
				var pounded_forward = Right_Main.get_level() * ( 1 + math.sin(pitch_rad) ) * ( 1 + math.sin(accel_fps) );
				var tk_fuel_diff = pounded_aft - pounded_forward;
				tk_gate_trans = fuel_flow_rate * ( 1 - ( math.abs(tk_fuel_diff) / 1300 ) );
				if ( tk_fuel_diff < 0 ) {
					tk_gate_trans = tk_gate_trans * -1
				}
				if ( tk_gate_trans > 0 and gal_level < tk_gate_trans or tk_gate_trans < 0 and t.get_level() < tk_gate_trans ) {
					tk_gate_trans = 0
				}
				gal_level -= tk_gate_trans;
			}

		} elsif ( j == 2 ) {
			if (
				feed_line_pressure_bf[1] > 5 and t.get_boost_pump()
				or collector_tank_diff[1] > 0 and ! Right_Wing.get_boost_pump()
			) {
				gal_level -= collector_tank_diff[1]
			}
			if ( Right_Wing.get_transfering() ) {
				gal_level += fuel_flow_rate
			}
			if ( TankGateValve.is_open() ) {
				gal_level += tk_gate_trans
			}

		} elsif ( j == 3 ) {
			if ( t.get_boost_pump() and feed_line_pressure_bf[1] > 5 ) {
				gal_level = gal_level - collector_tank_diff[1]
			}
			if ( Right_Wing.get_transfering() ) {
				gal_level -= fuel_flow_rate
			}

		} elsif ( j == 4 ) {
			if ( t.get_boost_pump() and Right_External.get_boost_pump() ) {
				gal_level -= fuel_flow_rate / 2
			} elsif ( t.get_boost_pump() ) {
				gal_level -= fuel_flow_rate
			}

		} elsif ( j == 5 ) {
			if ( t.get_boost_pump() ) { gal_level -= fuel_flow_rate }

		} elsif ( j == 6 ) {
			if ( t.get_boost_pump() and Left_External.get_boost_pump() ) {
				gal_level -= fuel_flow_rate / 2
			} elsif ( t.get_boost_pump() ) {
				gal_level -= fuel_flow_rate
			}
		}

		if ( t.get_type() and t.get_fill_valve() ) {
			# External tanks to internal tanks fuel flow.
			if ( Left_External.get_boost_pump()
				or Fuse_External.get_boost_pump()
				or Right_External.get_boost_pump()
			) {
				gal_level += fuel_flow_rate / int_tanks_filled
			}
		}

		# Air to Air Refuel
		if ( t.get_fill_valve() and ( aa_refuel_flow > 0 )) {
			gal_level += aa_refuel_flow / ( int_tanks_filled + ext_tanks_filled )
		}

		# Tanks could not have a negative level.
		if ( gal_level < 0 ) { gal_level = 0 }

		t.set_level(gal_level);
		lbs_level = gal_level * PPG;
		gal_total += gal_level;
		lbs_total += gal_level * PPG;

	}

	TotalFuelGals.setValue(gal_total); # TODO delete 2D panels.
	TotalFuelLbs.setValue(lbs_total);
	# Prepare values for the A-10's fuel quantity gauge and warnings.
	FuelDiffLbs.setValue(math.abs(right_main_tank - left_main_tank));
	if ( FuelGaugeVolts.getValue() < 23) {
		DspLeft.setValue( 0 );
		DspRight.setValue( 0 );
		DspDrum.setValue( 0 );
	} else {
		if ( FuelGaugeTest.getBoolValue() ) {
			DspLeft.setValue( 3000 );
			DspRight.setValue( 3000 );
			DspDrum.setValue( 6000 );
		} else {
			DspDrum.setValue( lbs_total );
			if(fuel_dsp_sel == -1) {
				DspLeft.setValue( ( left_wing_tank + left_main_tank ) );
				DspRight.setValue( ( right_wing_tank + right_main_tank ) );
			} elsif ( fuel_dsp_sel == 0 ) {
				DspLeft.setValue( left_main_tank );
				DspRight.setValue( right_main_tank );
			} elsif ( fuel_dsp_sel == 1 ) {
				DspLeft.setValue( left_wing_tank );
				DspRight.setValue( right_wing_tank );
			} elsif (fuel_dsp_sel == 2 ) {
				DspLeft.setValue( Left_External.get_level_lbs() );
				DspRight.setValue( Right_External.get_level_lbs() );
			} elsif ( fuel_dsp_sel == 3 ) {
				DspLeft.setValue( Fuse_External.get_level_lbs() );
				DspRight.setValue( 0 );
			}
		}
	}
	counter += 1;
	if ( counter == 3 ) { counter = 0 } 
}


var check_DC_pump = func {
	# DC boost pump in Left Main Tank, feed APU at start.
	var DC_bp = 0;
	if (
		APU_Switch.getBoolValue()
		or A10engines.LeftEngine.get_alt_throttle_pos() >= 0.03
		or A10engines.RightEngine.get_alt_throttle_pos() >= 0.03
	) {
		if (
			Left_Wing.get_level_lbs() > 1.56
			and ! Left_Wing.get_boost_pump() and ! Left_Main.get_boost_pump()
			and DC_Boost_Serv.getBoolValue() and DC_ESSEN_ok
		) {
			DC_bp = 1
		}
	}
	DC_boost_pump.setBoolValue(DC_bp);
}


var check_fill_valve = func(t) {
	var f_valve = t.get_fill_valve();
	var i = t.get_index();
	if ( i == 0 or i == 3 ) {     # Wing tanks.
		if ( ! t.get_control_fill_dis() and t.get_level() < 246 and L_DC_ok) {
			f_valve = 1
		} elsif ( (t.get_fill_valve() and t.get_level() > 308) or t.get_control_fill_dis() or !L_DC_ok ) { 
			f_valve = 0
		}
	} elsif ( i == 1 or i == 2 ) {     # Main tanks.
		if ( ! t.get_control_fill_dis() and t.get_level() < 446 and L_DC_ok ) {
			f_valve = 1
		} elsif ( t.get_fill_valve() and t.get_level() > 508 or t.get_control_fill_dis()  or !L_DC_ok ) {
			f_valve = 0
		}
	} else {     # External tanks
		f_valve = 0;
		if ( t.get_level() < 595 and L_DC_ok and t.get_capacity() > 0 ) {
			f_valve = 1
		}
	}
	t.set_fill_valve(f_valve);
}



# Controls ################
var fill_dis_toggle = func(n) {
	foreach (var t; Tank.list) {
		if ( t.get_index() == n ) { t.toggle_control_fill_dis() }
	}
}


var aar_receiver_lever = func(rec_pos=0) {
	if ( rec_pos == 0 ) {
		ReceiverLever.setBoolValue(0);
		DoorLock.setBoolValue(0);
		RefuelState.setValue(0);
	} else {
		ReceiverLever.setBoolValue(1);
		# TODO: - Open the slipway-door by aerodynamic effect in case of right
		# hydraulic system failure.
		# - Delay the opening.
		if ( HydPsi.getValue() > 900 and L_DC_ok and RefuelServ.getBoolValue()) {
			DoorLock.setBoolValue(1);
			RefuelState.setValue(1);
		}
	}
}


# - Resets Air to Air Refuel system from DISCONNECT to READY (no need of the
# RCVR lever) OR put the system from LATCHED to DISCONNECT.
# You can bind one of your joystick buttons to this function.
var aar_reset_button = func {
	var r = RefuelState.getValue();
	if ( r == 3 ) { RefuelState.setValue(1) } elsif ( r == 2 ) { RefuelState.setValue(3) }
}


var aar_fuel_flow = func( List ) {
	var refuel_flow = 0;
	foreach( var tk; List ) {
		if ( tk.getNode("refuel/contact", 1).getBoolValue() and tk.getNode("tanker", 1).getBoolValue() ) {			
			refuel_flow = 15.625 * A10.UPDATE_PERIOD # gals. (About 6000lbs/min)
		}
	}
	return refuel_flow;
}


var fuel_sel_knob_move = func(arg0) {
	var knob_pos = FuelDspSel.getValue();
	if ( arg0 == 1 and knob_pos < 3 ) {
		knob_pos = knob_pos + 1
	} elsif ( arg0 == -1 and knob_pos > -1 ) {
		knob_pos = knob_pos - 1
	}
	FuelDspSel.setValue(knob_pos);
}



# Classes ################
Tank = {
	new : func (name, number, type, selected, control_fill_dis, fill_valve, density) {
		var obj = { parents : [Tank]};
		obj.prop         = props.globals.getNode("consumables/fuel").getChild("tank", number , 1);
		obj.name         = obj.prop.getNode("name", 1);
		obj.capacity     = obj.prop.getNode("capacity-gal_us", 1);
		obj.ppg          = obj.prop.getNode("density-ppg", 1);
		obj.level_gal_us = obj.prop.getNode("level-gal_us", 1);
		obj.level_lbs    = obj.prop.getNode("level-lbs", 1);
		obj.transfering  = obj.prop.getNode("transfering", 1);
		obj.type         = obj.prop.getNode("type", 1);
		obj.boost_pump   = obj.prop.getNode("boost_pump", 1);
		obj.fill_valve   = obj.prop.getNode("fill-valve", 1);
		obj.ppg.setDoubleValue(density);
		obj.prop.getChild("name", 0, 1).setValue(name);
		obj.prop.getChild("selected", 0, 1).setBoolValue(selected);
		obj.prop.getChild("type", 0, 1).setBoolValue(type);
		obj.prop.getChild("transfering", 0, 1).setBoolValue(0);
		obj.prop.getChild("fill-valve", 0, 1).setBoolValue(fill_valve);

		obj.control_prop     = props.globals.getNode("controls/fuel").getChild("tank", number , 1);
		obj.control_fill_dis = obj.control_prop.getNode("fill-dis", 1);
		obj.control_prop.getChild("fill-dis", 0, 1).setBoolValue(control_fill_dis);

		append(Tank.list, obj);
		return obj;
	},
	get_capacity : func {
		return me.capacity.getValue(); 
	},
	get_ppg : func {
		return me.ppg.getValue();
	},
	get_type : func {
		return me.type.getBoolValue(); 
	},
	get_level : func {
		return me.level_gal_us.getValue();	
	},	
	set_level : func (gals_us){
		if(gals_us < 0) gals_us = 0;
		me.level_gal_us.setDoubleValue(gals_us);
		me.level_lbs.setDoubleValue(gals_us * me.ppg.getValue());
	},
	get_level_lbs : func {
		return me.level_lbs.getValue();	
	},
	get_transfering : func {
		return me.transfering.getBoolValue();
	},
	set_transfering : func (transfering){
		me.transfering.setBoolValue(transfering);
	},
	get_amount : func (dt, ullage) {
		var amount = (flowrate_lbs_hr / (me.ppg.getValue() * 60 * 60)) * dt;
		if(amount > me.level_gal_us.getValue()) {
			amount = me.level_gal_us.getValue();
		} 
		if(amount > ullage) {
			amount = ullage;
		} 
		var flowrate_lbs = ((amount/dt) * 60 * 60) * me.ppg.getValue();
		return amount
	},
	get_ullage : func () {
		return me.get_capacity() - me.get_level()
	},
	get_name : func () {
		return me.name.getValue();
	},
	get_index : func () {
		return me.prop.getIndex();
	},
	set_transfer_tank : func (dt, tank) {
		foreach (var t; Tank.list) {
			if(t.get_name() == tank)  {
				transfer = me.get_amount(dt, t.get_ullage());
				me.set_level(me.get_level() - transfer);
				t.set_level(t.get_level() + transfer);
			} 
		}
	},
	get_boost_pump : func () {
		return me.boost_pump.getBoolValue();
	},
	set_boost_pump : func (n) {
		me.boost_pump.setBoolValue(n);
	},
	get_fill_valve : func () {
		return me.fill_valve.getBoolValue();
	},
	set_fill_valve : func (n) {
		me.fill_valve.setBoolValue(n);
	},
	get_control_fill_dis : func () {
		return me.control_fill_dis.getBoolValue();
	},
	toggle_control_fill_dis : func () {
		me.control_fill_dis.setBoolValue( ! me.control_fill_dis.getBoolValue() );
	},
	list : [],
};

var Valve = {
	new: func(prop, initial_pos) {
		var obj = { parents: [Valve] };
		obj.prop = props.globals.getNode(prop, 1);
		obj.prop.setBoolValue(initial_pos);
		append(Valve.list, obj);
		return obj;
	},
	is_open : func {
		return me.prop.getBoolValue();
	},
	set_close : func {
		me.prop.setBoolValue(0);
	},
	set_open : func {
		me.prop.setBoolValue(1);
	},
	toggle : func {
		me.prop.setBoolValue(!me.prop.getValue());
	},
	list : [],
};
