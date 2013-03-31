
fire_MG = func {
	setprop("/controls/armament/trigger", 1);
}

stop_MG = func {
	setprop("/controls/armament/trigger", 0); 
}

var flash_trigger = props.globals.getNode("controls/armament/trigger", 0);

##########################################################
# General initializers
#  

var r_gun1_ammo_count="ai/submodels/submodel[0]/count";  
var r_gun2_ammo_count="ai/submodels/submodel[1]/count";
var r_gun3_ammo_count="ai/submodels/submodel[2]/count"; 
var l_gun1_ammo_count="ai/submodels/submodel[3]/count";
var l_gun2_ammo_count="ai/submodels/submodel[4]/count";
var l_gun3_ammo_count="ai/submodels/submodel[5]/count";




##############################################################
#reload guns
#
#Guns generally cannot be reloaded in flight.  It requires landing, 
#stop, and reload before taking off again.
# 
# Note that tracers are modeled as bullets that include a visual model but
# no impact.  They fire along with 1 of every three or four bullets to simulate
# a tracer round every 4 rounds.

reload_guns  = func {

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  
  #only allow it if on ground, stopped OR if it's already set to unlimited mode
  if ( ( groundspeed < 5 and engine_rpm < 5 )  
         or getprop ( r_gun1_ammo_count)== -1 ) {
    
    setprop ( r_gun1_ammo_count, 400); #ammo r
    setprop ( r_gun2_ammo_count, 400); #ammo r
    setprop ( r_gun3_ammo_count, 400); #ammo r
    setprop ( l_gun1_ammo_count, 400); #ammo r
    setprop ( l_gun2_ammo_count, 400); #ammo r
    setprop ( l_gun3_ammo_count, 400); #ammo r                
    
    gui.popupTip ("Guns reloaded--400 rounds in each gun.", 5)
    
  } else {
   
    gui.popupTip ("You must be on the ground and engines dead stopped to re-load guns.",5)
  
  }

}  

##############################################################
#unlimited ammo
#
#For testing only, of course!
# 

unlimited_guns = func {

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  

    
    setprop ( r_gun1_ammo_count, -1); #ammo r
    setprop ( r_gun2_ammo_count, -1); #ammo r
    setprop ( r_gun3_ammo_count, -1); #ammo r
    setprop ( l_gun1_ammo_count, -1); #ammo r
    setprop ( l_gun2_ammo_count, -1); #ammo r
    setprop ( l_gun3_ammo_count, -1); #ammo r  
       
    gui.popupTip ("Guns set to unlimited mode--definitely not realistic and only for testing!  Select 'Reload Guns' to revert to limited ammo.",7)
  
}

