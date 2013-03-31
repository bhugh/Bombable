
fire_MG = func {
	setprop("/controls/armament/trigger", 1);
}

stop_MG = func {
	setprop("/controls/armament/trigger", 0); 
}

var flash_trigger = props.globals.getNode("controls/armament/trigger", 0);



##########################################################
# General initiatizers
#  
var ammo_weight=1.4/20; # 20 rounds of .303 180gr ammo weighs 1.4 pounds 
                    # per http://www.ammo-sale.com/proddetail.asp?prod=1699# 

var r_gun_ammo_count="ai/submodels/submodel[0]/count";  
var r_gun_tracer_count="ai/submodels/submodel[1]/count"; 

    


##############################################################
#reload guns
#
# According to this source the Vickers couldn't be releoaded 
# in flight--it took a man on the ground and one in the 
# cockpit:
# 
# http://www.theaerodrome.com/forum/aircraft/40149-reloading-guns.html
# 
# This we require landed and engines off before reloading.
# 
# Per this source, British Camels with Vickers guns typically
# loaded 400 rounds:
# 
# http://www.theaerodrome.com/forum/aircraft/29896-bullets-guns.html
# 
# Note that tracers are modeled as bullets that include a visual model but
# no impact.  They fire along with 1 of every four bullets to simulate
# a tracer round every 4 rounds.

reload_guns  = func {

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  
  #only allow it if on ground, stopped OR if it's already set to unlimited mode
  if ( ( groundspeed < 5 and engine_rpm < 5 )  
         or getprop ( r_gun_ammo_count)== -1 ) {
    
    setprop ( r_gun_ammo_count, 400); #ammo r
    setprop ( r_gun_tracer_count, 110); #tracer r
    
    gui.popupTip ("Gun reloaded--an ammunition belt with 400 rounds is in the gun.", 5)
    
  } else {
   
    gui.popupTip ("You must be on the ground and engines dead stopped to re-load guns--this is a two-person job with one on the ground and one in the cockpit.",5)
  
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
  

    
    setprop ( r_gun_ammo_count, -1); #ammo r
    setprop ( r_gun_tracer_count, -1); #tracer r

   
    gui.popupTip ("Guns set to unlimited mode--definitely not realistic and only for testing!  Select 'Reload Guns' to revert to limited ammo.",7)
  
}

 
