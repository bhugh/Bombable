##########################################################
# General initializers
#  
var ammo_weight=1.4/20; # 20 rounds of .303 180gr ammo weighs 1.4 pounds 
                    # per http://www.ammo-sale.com/proddetail.asp?prod=1699# 

var r_gun_ammo_count="ai/submodels/submodel[0]/count";  
var l_gun_ammo_count="ai/submodels/submodel[3]/count";
var r_gun_tracer_count="ai/submodels/submodel[1]/count"; 
var l_gun_tracer_count="ai/submodels/submodel[4]/count";
var r_gun_smoke_count="ai/submodels/submodel[2]/count";
var l_gun_smoke_count="ai/submodels/submodel[5]/count";

var r_ammo_weight="yasim/weights/ammo-r-lb";
var l_ammo_weight="yasim/weights/ammo-l-lb";



########################################################
#Gun vibration effect
#borrowed/modded from the neat gun/vibration effect in the A-10

  
  
  props.globals.getNode("sim/current-view/z-offset-m-saved", 1).setDoubleValue(0); #create the node


var init_gun_vibration  = func ( trigger_prop, vibAmount, vibTime ) { 
  print ("Gun vibrations initialized");
  
  var trigger_node   = props.globals.getNode(trigger_prop);


  setlistener( trigger_prop , func( Trig ) {

    var z_pov         = props.globals.getNode("sim/current-view/z-offset-m");
  
    var z_store        = props.globals.getNode("sim/current-view/z-offset-m-saved", 1);

    # only if the trigger is pulled AND there is ammo in at least one gun
  	if ( Trig.getBoolValue() and 
          ( getprop ( r_gun_ammo_count) or getprop (l_gun_ammo_count)  )  ) {
          
  	  #print ("vibrating");

      # gun vibrations effect
      z_store.setDoubleValue( z_pov.getValue()+z_store.getValue());
   
  
  		gun_vibs(vibAmount, vibTime, z_pov.getValue(), z_pov, trigger_node );

  	} else {

  	  #print ("stop vibrating");
  	  #v=0 means stop vibrating & return to position in z_povhold
 
  		gun_vibs(0, vibTime, z_store.getValue(), z_pov, trigger_node);
      z_store.setDoubleValue(0);
      
    }
  }, 0,0 ); #make the setlistener respond only when the value is changed.


}


#todo:  This could probably mess up your view (zpos) if you change view z position while shooting, or change views while shooting.

var gun_vibs = func(vibAmount, vibTime, zpov,z_pov, trigger_node) {
	if (getprop("sim/current-view/view-number") == 0) {
	
	
	  #Todo: make vibrations stop when out of ammo, rather than just
	  # when the trigger is pressed	  
		if ( vibAmount != 0 and trigger_node.getValue() ) { 
			var newZpos = vibAmount+zpov;
			z_pov.setValue(newZpos);
 
			settimer( func { gun_vibs (-vibAmount,vibTime, zpov, z_pov, trigger_node) }, vibTime); 
		} else { z_pov.setValue(zpov); }
	}
}


##############################################################
#init gun vibration
#
#init the gun vibration subroutine with the trigger you want
vibAmount=0.0005;
# two guns running @ one round every .1333 seconds, approx.   
#each round has an up & down vibration.  Thus:
vibTime=0.1333/4;		       
settimer(func { init_gun_vibration ("controls/armament/trigger", vibAmount, vibTime); }, 5);
#print ("gun vibrations init #1");


##############################################################
#update ammo weight update every 5 seconds
#
# todo: make this work for other FDM other than YASIM
# 
var update_ammo_weight = func {

                         
    setprop (r_ammo_weight, ammo_weight * getprop(r_gun_ammo_count));
    setprop (l_ammo_weight, ammo_weight * getprop(l_gun_ammo_count));

    #updating once every 5 seconds should be sufficient--
    #this is fairly lightweight ammo 
    #and you can only shoot about 4 pounds from each gun in 5 seconds.           
    settimer (update_ammo_weight, 5);
}


##############################################################
#init update ammo weight
#
# todo: make this work for other FDM other than YASIM


#start the timer to update the ammo weights
settimer (update_ammo_weight, 5);
    


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
    setprop ( r_gun_ammo_count, 400); #ammo l
    setprop ( r_gun_tracer_count, 100); #tracer r
    setprop ( r_gun_tracer_count, 100); #tracer l
    setprop ( r_gun_smoke_count, 400); #smoke r
    setprop ( r_gun_smoke_count, 400); #smoke l
    
    gui.popupTip ("Guns reloaded--an ammunition belt with 400 rounds in each gun.", 5)
    
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
    setprop ( r_gun_ammo_count, -1); #ammo l
    setprop ( r_gun_tracer_count, -1); #tracer r
    setprop ( r_gun_tracer_count, -1); #tracer l
    setprop ( r_gun_smoke_count, -1); #smoke r
    setprop ( r_gun_smoke_count, -1); #smoke l

   
    gui.popupTip ("Guns set to unlimited mode--definitely not realistic and only for testing!  Select 'Reload Guns' to revert to limited ammo.",7)
  
}

 


#print ("gun vibrations init #1");

