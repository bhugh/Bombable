# Garrett A-10 auxiliary power unit (APU)
# ---------------------------------------
# Authors: David Bastien and Alexis Bory

# - APU starts can be made up to an altitude of 15,000ft to 20.000ft.
# - APU stalls above 26.000ft.
# - APU pressure output is sufficient to start up to an engine below 10.000ft.
# - During ground operation, if the APU EGT exceed 720°C, it will be
# automatically shutdown. If EGT exceed 850°C the APU is killed.
# - Fuel consumption @ rpm 100% => 206pph. (Guess from B737-200A APU.)
# (206 pph / 3600 sec / 100 rpm = 0.000572 pps @ 1 rpm).

# TODO :
# - if APU gen is PWR and power_source is not apu then light on.
# - APU gen as to be reset after an APU shut down in order to the generator to
# operate again.
# - How to trigger a > 850°C over heating?
# - Simulate APU generator cooling fan not receiving power and generator failing
# due to overtemp.
# - Fuel consumption under load = 263pph.

var APU_Start_Sw  = props.globals.getNode("controls/APU/off-start-switch");
var APU_Gen_Sw    = props.globals.getNode("controls/APU/generator-switch");
var APU_Serv      = props.globals.getNode("controls/APU/serviceable");
var StartState    = props.globals.getNode("sim/model/A-10/systems/apu/start-state");
var Running       = props.globals.getNode("sim/model/A-10/systems/apu/running");
var APU_Rpm       = props.globals.getNode("sim/model/A-10/systems/apu/rpm-norm");
var APU_Temp      = props.globals.getNode("sim/model/A-10/systems/apu/temp");
var APU_OverTemp  = props.globals.getNode("sim/model/A-10/systems/apu/egt-overt", 1);
var APU_OutofFuel = props.globals.getNode("sim/model/A-10/systems/apu/out-of-fuel");
var APU_FuelCons  = props.globals.getNode("sim/model/A-10/systems/apu/fuel-consumed-lbs");
var APU_StartSys  = props.globals.getNode("systems/electrical/outputs/apu-start-system", 1);
var APU_GenV      = props.globals.getNode("systems/electrical/APU-gen-volts", 1);
var APU_Light     = props.globals.getNode("systems/A-10-electrical/apu-gen-caution-light", 1);

var L_Gen_Sw      = props.globals.getNode("controls/electric/engine[0]/generator", 1);
var R_Gen_Sw      = props.globals.getNode("controls/electric/engine[1]/generator", 1);
var WoW           = props.globals.getNode("gear/gear[1]/wow", 1);
var Deg_C         = props.globals.getNode("environment/temperature-degc");
var Press_InHg    = props.globals.getNode("environment/pressure-inhg");

var apu_rpm_goal  = 0;
var apu_temp_goal = 0;
var airpress_coef = 0;
var last_raw_temp = 0;
APU_Rpm.setValue(0);


var update_loop = func {
	var fuel_cons    = 0;
	var apu_rpm       = APU_Rpm.getValue();
	var apu_temp      = APU_Temp.getValue();
	var over_temp     = APU_OverTemp.getBoolValue();
	var apu_start_sys = APU_StartSys.getValue();
	var apu_gen_volts = APU_GenV.getValue();
	var out_of_fuel   = APU_OutofFuel.getBoolValue();
	var start_sw      = APU_Start_Sw.getBoolValue();
	var state         = StartState.getValue(); # Start/stop time counter.
	var running       = Running.getBoolValue();
	var wow           = WoW.getBoolValue();
	var serviceable   = APU_Serv.getBoolValue();

	var ext_temp      = Deg_C.getValue();
	var p_inhg        = Press_InHg.getValue();

	airpress_coef = (( p_inhg - 20 ) * 22.5 / p_inhg ) - 3.3;

	if ( ! out_of_fuel and apu_start_sys >= 23 and running and ! over_temp and serviceable ) {
		if ( state < 1 ) {
			if ( p_inhg > 13.7 ) {
				# RPM increase during +/- 60 sec up to 100%
				# Temp stabilizes at 600°C 30 sec after start.
				apu_rpm_goal = ((math.sin((state * 3) + 4.7) + 1) * 48) + (0.046 * apu_rpm);
				if ( state < 0.72 ) {
					var ts = state - 0.2;
					apu_temp_goal = (((atan(( ts * 85.5)-9)+(math.sin( ts * 9)*0.39))/4.2)+0.35) * 950;
					if ( apu_temp_goal < 0 ) { apu_temp_goal = 0 }
				}
				StartState.setValue( state + 0.004 );
			} else {
				running = 0;
				return;
			}
		}
		if ( p_inhg == 0 ) { p_inhg = 0.0001 } # Aliens might take us outside atmosphere.
		apu_rpm = apu_rpm_goal + airpress_coef;
		apu_temp = ((apu_temp_goal / 100) * (100 + airpress_coef)) + ext_temp;
		if ( apu_rpm > 10 ) {
			fuel_cons = APU_FuelCons.getValue();
			fuel_cons += apu_rpm * 0.00057222222 * A10.UPDATE_PERIOD;
		}
		if ( apu_temp > 760 and wow and apu_rpm >= 60) {
			APU_OverTemp.setBoolValue(1);
			running = 0;
		}
		if ( apu_temp > 850 and apu_rpm >= 75) {
			APU_Serv.setBoolValue(0);
			running = 0;
		}
		if ( p_inhg < 10 ) {
			running = 0;
		}
	} else {
		if ( apu_rpm >= 0.3 ) {
			apu_rpm -= 0.3;
		}
		var min_temp = ext_temp + 5;
		if ( apu_temp > min_temp ) {
			apu_temp -= 0.5 + ( apu_rpm / 50 );
		}
		if ( StartState.getValue() >= 0.004 ) {
			StartState.setValue( state - 0.004 );
		}
	}

	if ( APU_OverTemp.getBoolValue() and ! start_sw and apu_rpm < 10 ) {
		APU_OverTemp.setBoolValue(0)
	}

	APU_Rpm.setValue(apu_rpm);
	APU_Temp.setValue(apu_temp);
	APU_FuelCons.setValue(fuel_cons);
	Running.setBoolValue(running);

	var apu_light = 0;
	if ( ! start_sw and APU_Gen_Sw.getBoolValue() ) { apu_light = 1 }
	l_gen_sw = L_Gen_Sw.getBoolValue();
	r_gen_sw = R_Gen_Sw.getBoolValue();
	if ( apu_gen_volts > 23 and ( l_gen_sw or r_gen_sw ) ) { apu_light = 1 }
	APU_Light.setBoolValue(apu_light);
}


# Controls ################
var toggle_off_start_switch = func {
	var sw = APU_Start_Sw.getBoolValue();
	if ( ! sw ) {
		APU_Start_Sw.setBoolValue(1);
		if ( APU_Serv.getBoolValue() and ! APU_OverTemp.getBoolValue() ) {
			APU_StartSys.setValue(electrical.DC_ESSEN_bus_volts);
			Running.setBoolValue(1);
		}
	} else {
		APU_Start_Sw.setBoolValue(0);
		APU_StartSys.setValue(0);
		Running.setBoolValue(0);
	}
}

# Utils ###################
var atan = func {
  return math.atan2(arg[0], 1);
}

