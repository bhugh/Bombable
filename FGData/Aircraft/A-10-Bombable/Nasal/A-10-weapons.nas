var a10weapons    = props.globals.getNode("sim/model/A-10/weapons");
var arm_sw        = props.globals.getNode("sim/model/A-10/weapons/master-arm-switch");
var aim9_knob     = props.globals.getNode("sim/model/A-10/weapons/dual-AIM-9/aim9-knob");
var gun_running   = props.globals.getNode("sim/model/A-10/weapons/gun/running[0]");
var gr_switch     = props.globals.getNode("sim/model/A-10/weapons/gun-rate-switch");
var gun_count     = props.globals.getNode("ai/submodels/submodel[1]/count");
var GunReady      = props.globals.getNode("sim/model/A-10/weapons/gun/ready");
var GunHydrDriveL = props.globals.getNode("sim/model/A-10/weapons/gun/hydr-drive-serviceable[0]");
var GunHydrDriveR = props.globals.getNode("sim/model/A-10/weapons/gun/hydr-drive-serviceable[1]");
var HydrPsiL      = props.globals.getNode("systems/A-10-hydraulics/hyd-psi[0]");
var HydrPsiR      = props.globals.getNode("systems/A-10-hydraulics/hyd-psi[1]");
var z_pov         = props.globals.getNode("sim/current-view/z-offset-m");

var vibs_mult     = 1;
var lastGunCount = 0;
var z_povhold = 0;
var vibs_amt = .062500345;
var vibs_time_sec=.1250004352;

# Init
var initialize = func() {
	setlistener("controls/armament/trigger", func( Trig ) {
		if ( Trig.getBoolValue()) {
			A10weapons.fire_gau8a();
		} else {
			A10weapons.cfire_gau8a(); }
	});
	# gun vibrations effect
	z_povhold = z_pov.getValue();
	
	#bhugh, 2011-09, this updates our weapons buttons and sets them so they can be released, 
  #based on the pre-loaded/default weapons config in the -set.xml file
	update_stations();

}

var fire_gau8a = func {
	var gunRun = gun_running.getValue();
	var gready = update_gun_ready();
	if (gready and !gunRun) {
		gun_running.setBoolValue(1);
		gunRun = 1;
		#gau8a_vibs(0.002, z_pov.getValue());
		gau8a_vibs(vibs_amt, z_pov.getValue());
	} elsif(!gready) {
		gun_running.setBoolValue(0);
		return;
	}
	if (gunRun) {
		# update gun count and yasim weight
		var realGunCount = gun_count.getValue();
		if (realGunCount==nil) realGunCount==0;
		# init lastGunCount

		#The next two lines are a trick to shoot only one round of each 7 
		#but having 7 submodels shoot at once. Thus, same rounds/second
		#as the spect despite the fact the FG's FR is slower than that (usually).
		#Prob is adjusting the rate of ammo.
    # while reducing the ammo weight by 7X the amount 'really' shot by FG
		#in order to give operational equivalence to a real A-10
		#However for Bombable we need to fire 'real' rounds or they don't hit anything.
    #We try to make this work better by adjusting in A-10-submodels.xml but
    #dispense with the trick here.  Brent Hugh 2011-09-10. 
		#if((lastGunCount == 0) and (realGunCount > 0)) { lastGunCount = realGunCount + 1; }
		    #realGunCount -= (lastGunCount - realGunCount) * 7;
		if(realGunCount < 0) { realGunCount = 0 }
		gun_count.setValue(realGunCount);
		setprop("yasim/weights/ammunition-weight-lbs", (realGunCount*0.9369635));
		# for the next loop
		lastGunCount = realGunCount;
	}
}

var cfire_gau8a = func {
	gun_running.setBoolValue(0);
	update_gun_ready();
}

var gau8a_vibs = func(v, zpov) {
	#if (getprop("sim/current-view/view-number") == 0) {
		if (gun_running.getBoolValue()) {
		  #vibrates slightly in heading & pitch to duplicate inaccuracy in GAU firing
		  #setprop ("/controls/flight/elevator", getprop("/controls/flight/elevator")
      #  +v*vibs_mult );
		  setprop ("/controls/flight/rudder", getprop("/controls/flight/rudder") 
         + v*vibs_mult );
		  
		  vibs_mult=2;
			#var newZpos = v+zpov;
			#z_pov.setValue(newZpos);
			settimer( func { gau8a_vibs(-v, zpov) }, vibs_time_sec);
		} else { 
      #z_pov.setValue(z_povhold);
      vibs_mult=1; 
      #setprop ("/controls/flight/elevator", getprop("/controls/flight/elevator")
      #  +v*vibs_mult );
		  setprop ("/controls/flight/rudder", getprop("/controls/flight/rudder") 
         + v*vibs_mult );
      
    }
	#}
}

var update_gun_ready = func() {
	var ready = 0;
	# TODO: electrical bus should be DC ARM BUS
	if (gr_switch.getValue() and arm_sw.getValue() == 1 and gun_count.getValue() > 0) {
		var drive_l = GunHydrDriveL.getValue();
		var drive_r = GunHydrDriveR.getValue();
		var psi_l   = HydrPsiL.getValue();
		var psi_r   = HydrPsiR.getValue();
		if (electrical.R_DC_bus_volts >= 24 and ((drive_l == 1 and psi_l > 900) or (drive_r == 1 and psi_r > 900))) {
			ready = 1;
		}
	}
	GunReady.setBoolValue(ready);
	return ready;
}

# station selection
# -----------------
# Selects one or several stations. Each has to be loaded with the same type of
# ordnance. Selecting a new station loaded with a different type deselects the
# former ones. Selecting  an allready selected station deselect it.
# Activates the search sound flag for AIM-9s (wich will be played only if the AIM-9
# knob is on the correct position). Ask for deactivation of the search sound flag
# in case of station deselection.
var stations      = props.globals.getNode("sim/model/A-10/weapons/stations");
var stations_list = stations.getChildren("station");
var weights       = props.globals.getNode("sim").getChildren("weight");
var aim9_knob     = a10weapons.getNode("dual-AIM-9/aim9-knob");
var aim9_sound    = a10weapons.getNode("dual-AIM-9/search-sound");
var cdesc = "";

var select_station = func {
	var target_idx = arg[0];
	setprop("controls/armament/station-select", target_idx);
	var desc_node = "sim/model/A-10/weapons/stations/station[" ~ target_idx ~ "]/description";
	#print("sim/model/A-10/weapons/stations/station[" ~ target_idx ~ "]/description");
	cdesc = props.globals.getNode(desc_node).getValue();
	#print("select_station.cdesc: " ~ cdesc);
	var sel_list = props.globals.getNode("sim/model/A-10/weapons/selected-stations");
	foreach (var s; stations_list) {
		idx = s.getIndex();
		var sdesc = s.getNode("description").getValue();
		var ssel = s.getNode("selected");
		var tsnode = "s" ~ idx;
		if ( idx == target_idx ) {
			if (ssel.getBoolValue()) {
				ssel.setBoolValue(0);
				sel_list.removeChildren(tsnode);
				if ( sdesc == "dual-AIM-9" ) {
					deactivate_aim9_sound();
				}
			} else {
				ssel.setBoolValue(1);
				var ts = sel_list.getNode(tsnode, 1);
				ts.setValue(target_idx);
				if ( sdesc == "dual-AIM-9") {
					aim9_sound.setBoolValue(1);
				}
			}
		} elsif ( cdesc != sdesc ) {
			# TODO: code triple and single MK82 mixed release ? 
			ssel.setBoolValue(0);
			sel_list.removeChildren(tsnode);
			if ( sdesc == "dual-AIM-9" ) {
				deactivate_aim9_sound();
			}
		}
	}
}


# station release
# ---------------
# Handles ripples and intervales.
# Handles the availability lights (3 green lights each station).
# LAU-68, with 7 ammos by station turns only one light until the dispenser is empty.
# Releases and substract the released weight from the station weight.
# Ask for deactivation of the search sound flag after the last AIM-9 has been released.
var sl_list = 0;

var release = func {
	var arm_volts = props.globals.getNode("systems/electrical/R-AC-volts").getValue();
	var asw = arm_sw.getValue();
	if ( asw != 1 or arm_volts < 24 )	{ return; }
	sl_list = a10weapons.getNode("selected-stations").getChildren();
	var rip = a10weapons.getNode("rip").getValue();
	var interval = a10weapons.getNode("interval").getValue();
	# FIXME: riple compatible release types should be defined in the foo-set.file 
	if ( cdesc == "LAU-68" or cdesc == "triple-MK-82-LD" or cdesc == "single-MK-82-LD") {
		release_operate(rip, interval);
	} else {
		release_operate(1, interval);
	}
}

var release_operate = func(rip_counter, interval) {
	foreach(sl; sl_list) {
		var slidx = sl.getValue();
		var snode = "sim/model/A-10/weapons/stations/station[" ~ slidx ~ "]";		
		var s = props.globals.getNode(snode);
		var wnode = "sim/weight[" ~ slidx ~ "]";		
		var w = props.globals.getNode(wnode);
		var wght = w.getNode("weight-lb").getValue();
		var awght = s.getNode("ammo-weight-lb").getValue();
		if ( cdesc == "LAU-68" ) { var lau68ready = s.getNode("ready-0"); } 
		var avail = s.getNode("available");
		var a = avail.getValue();
		if ( a != 0 ) {
			if ( cdesc == "dual-AIM-9"  and aim9_knob.getValue() != 2 ) { return; }
			turns = a10weapons.getNode(cdesc).getNode("available").getValue();
			for( i = 0; i <= turns; i = i + 1 ) {
				var it = cdesc ~ "/trigger[" ~ i ~"]";
				var itrigger = s.getNode(it);
				var iready_node = "ready-" ~ i;
				var a = avail.getValue();
				if ( cdesc != "LAU-68" ) { var iready = s.getNode(iready_node); }
				var t = itrigger.getBoolValue();
				if ( !t and a > 0) {
					itrigger.setBoolValue(1);
					a -= 1;
					avail.setValue(a);
					rip_counter -= 1;
					wght -= awght;
					w.getNode("weight-lb").setValue(wght);
					if ( cdesc != "LAU-68" ) { iready.setBoolValue(0); }
					if ( a == 0 ) {
						if ( cdesc == "LAU-68" ) {
							lau68ready.setBoolValue(0);
						} elsif ( cdesc == "dual-AIM-9" ) {
							deactivate_aim9_sound();
						}
						s.getNode("error").setBoolValue(1);
					}
					if (rip_counter > 0 ) {
						settimer( func { release_operate(rip_counter, interval); }, interval);
					}
					return;
				}
			}
		}
	}
}


# Searchs if there isn't a remainning AIM-9 on a selected station before
# deactivating the search sound flag.
var deactivate_aim9_sound = func {
	aim9_sound.setBoolValue(0);
	var a = 0;
	foreach (s; stations.getChildren("station")) {
		var ssel = s.getNode("selected").getBoolValue();
		var desc = s.getNode("description").getValue();
		var avail = s.getNode("available");
		if ( ssel and desc == "dual-AIM-9"  ) {
			a += avail.getValue();
		}
		if ( a ) {
			aim9_sound.setBoolValue(1);
		}
	}
}


# link from the Fuel and Payload menu (gui.nas)
# ---------------------------------------------
# Called from the F&W dialog when the user selects a weight option
# and hijacked from gui.nas so we can call our update_stations().
# TODO: make the call of a custom func possible from inside gui.nas
gui.weightChangeHandler = func {
	var tankchanged = gui.setWeightOpts();

	# This is unfortunate.  Changing tanks means that the list of
	# tanks selected and their slider bounds must change, but our GUI
	# isn't dynamic in that way.  The only way to get the changes on
	# screen is to pop it down and recreate it.
	# TODO: position the recreated window where it was before.
	if(tankchanged) {
		update_stations();
		var p = props.Node.new({"dialog-name" : "WeightAndFuel"});
		fgcommand("dialog-close", p);
		gui.showWeightDialog();
	}
}

var update_stations = func {
	var a = nil;
	foreach (w; weights) {
		var idx = w.getIndex();
		var weight = 0;
		var desc = w.getNode("selected").getValue();
		if ( desc == "600 Gallons Fuel Tank" ) {
			desc = "tank-600-gals";
		}
		var type = a10weapons.getNode(desc);
		var snode = "sim/model/A-10/weapons/stations/station[" ~ idx ~ "]";
		var s = props.globals.getNode(snode);
		if ( desc != "none" ) {
			station_load(s, w, type);
		} else {
			station_unload(s, w);
		}
	}
}



# station load
# ------------
# Sets the station properties from the type definition in the current station.
# Prepares the error light or the 3 ready lights, then sets to false the
# necessary number of triggers (useful in the case of the submodels weren't
# already defined).
# Creates a node attached to the station's one and containing the triggers.
var station_load = func(s, w, type) {
	var weight = type.getNode("weight-lb").getValue();
	var ammo_weight = type.getNode("ammo-weight-lb").getValue();
	var desc = type.getNode("description").getValue();
	var avail = type.getNode("available").getValue();
	var readyn = type.getNode("ready-number").getValue();
	w.getNode("weight-lb").setValue(weight);
	s.getNode("ammo-weight-lb", 1).setValue(ammo_weight);
	s.getNode("description").setValue(desc);
	s.getNode("available").setValue(avail);
	if ( readyn == 0 ) {
		# non-armable payload case. (ECM pod, external tank...)
		s.getNode("error").setBoolValue(1);
		return;
	} else {
		s.getNode("error").setBoolValue(0);
	}
	if ( readyn == 1 ) {
		# single ordnance case.
		s.getNode("ready-0").setBoolValue(1);
	} elsif( readyn == 2 ) {
		# double ordnances case
		s.getNode("ready-0").setBoolValue(1);
		s.getNode("ready-1").setBoolValue(1);
	} else {
		# triple ordnances case
		s.getNode("ready-0").setBoolValue(1);
		s.getNode("ready-1").setBoolValue(1);
		s.getNode("ready-2").setBoolValue(1);
	} 
	for( i = 0; i < avail; i = i + 1 ) {
		# TODO: here to add submodels reload
		itrigger_node = desc ~ "/trigger[" ~ i ~ "]";
		t = s.getNode(itrigger_node, 1);
		t.setBoolValue(0);
	}
}


# station unload
# --------------
var station_unload = func(s, w) {
	w.getNode("weight-lb").setValue(0);
	s.getNode("ammo-weight-lb").setValue(0);
	#desc = s.getNode("description").getValue();
	s.getNode("description").setValue("none");
	s.getNode("available").setValue(0);
	s.getNode("ready-0").setBoolValue(0);
	s.getNode("ready-1").setBoolValue(0);
	s.getNode("ready-2").setBoolValue(0);
	s.getNode("error").setBoolValue(1);
}


# Armament panel switches
# -----------------------

var master_arm_switch = func(swPos=0) {
	# 3 positions MASTER ARM switch
	var mastArmSw = arm_sw.getValue();
	if((mastArmSw < 1) and (swPos == 1)) {
		mastArmSw += 1;
	} elsif((mastArmSw > -1) and (swPos == -1)) {
		mastArmSw -= 1;
	}
	arm_sw.setIntValue(mastArmSw);
	update_gun_ready();
}

var gun_rate_switch = func() {
	# Toggle gun rate switch and update GUN READY light
	var gunRateSw = gr_switch.getValue();
	if(gunRateSw == 0) {
		gr_switch.setBoolValue(1);
	} else {
		gr_switch.setBoolValue(0);
	}
	update_gun_ready();
}

var aim9_knob_switch = func {
	var input = arg[0];
	var a_knob = aim9_knob.getValue();
	if ( input == 1 ) {
		if ( a_knob == 0 ) {
			aim9_knob.setValue(1);
		} elsif ( a_knob == 1 ) {
			aim9_knob.setValue(2);
		}
	} else {
		if ( a_knob == 2 ) {
			aim9_knob.setValue(1);
		} elsif ( a_knob == 1 ) {
			aim9_knob.setValue(0);
		}
	}
}




##############################################################
#reload guns for GAU-8
#
# Guns generally cannot be reloaded in flight--so if you are out
# of ammo, land and re-load.
#
# For Bombable/Brent Hugh, 2011-09
#


reload_guns  = func {

  var gau8_ammo_count="/ai/submodels/submodel[1]/count";  
  var a10_ammo_weight="/yasim/weights/ammunition-weight-lbs";

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  
  #only allow it if on ground, stopped OR if it's already set to unlimited mode
  if (  groundspeed < 5  ) {
    
    setprop ( gau8_ammo_count, 1174); #ammo loaded
    
    var bweight=1174*0.9369635; #.9369635 = weight of one round in lbs
		setprop(a10_ammo_weight, bweight);
    
    gui.popupTip ("GAU-8 reloaded--1174 rounds.", 5);
    
  } else {
   
    gui.popupTip ("You must be on the ground and at a dead stop to re-load ammo.",5);
  
  }

}  

##############################################################
#unlimited ammo for GAU-8
#
#For testing only, of course!
# 
# For Bombable/Brent Hugh, 2011-09
#

unlimited_guns = func {

    var gau8_ammo_count="/ai/submodels/submodel[1]/count";  
    var a10_ammo_weight="/yasim/weights/ammunition-weight-lbs";
 
    # note that the usual -1 = unlimited doesn't work because of some of the code above.
    #Also the ammo weighs quite a lot and so loading a lot means we'll have to cheat somewhere.
    # So it's simpler to just allow it to be reset to 1174 as often as desired.
    # 
    setprop ( gau8_ammo_count, 1174); #ammo loaded, 1174 piece

    var bweight=1174*0.9369635; #.9369635 = weight of one round in lbs
		setprop(a10_ammo_weight, bweight); #we'll add the weight of 1174 rounds
    
    gui.popupTip ("GAU-8 reloaded with another 1174 rounds while in the air--definitely not realistic and only for testing!",7);
  
}
