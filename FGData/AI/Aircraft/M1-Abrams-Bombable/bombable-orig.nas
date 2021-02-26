#####################################################
#This module implements three different but interrelated functions
#that can be used by, for example, AI objects and scenery objects:
#
# 1. BOMBABLE: Makes objects bombable.  They will detect hits, change livery according to damage, and finally start on fire and smoke when sufficiently damaged. There is also a function to change the livery colors
#
# 2. GROUND: Makes objects stay at ground level, adjusting pitch to match any slope they are on.  So, for instance, cars, trucks, or tanks can move and always stay on the ground, drive up slopes somewhat realistically, etc. Ships can be placed in any lake and will automatically find their correct altitude, etc.
#
# 3. LOCATE: Usually AI objects return to their initial start positions when FG re-inits (ie, file/reset). This function saves and maintains their previous position prior to the reset
#
#TYPICAL USAGE
#
#Note the that object's node name can be found using cmdarg().getPath();
#
#<PropertyList>
#...
# <nasal>
#...
#  <load>
#      var node= cmdarg().getPath();
#      altadjust=3; #distance, in feet, to add to your object's altitude
#      ground_init ( node, altadjust );
#      location_init ( node )
#      var listenerid = bombable_init ( node, 
#          "Models/livery_nodamage.png", 
#          "Models/livery_slightdamage.png", 
#          "Models/livery_highdamage.png");
#  </load>
#  <unload>
#      var node= cmdarg().getPath();  
#      ground_del( node );
#      location_del (node);
#      bombable_del( node , listenerid );
#  </unload>
# </nasal>  
#</PropertyList>
#
#TO CHANGE LIVERY COLORS
# Set livery color (including slightly and completely damaged)
# Example:
#
#      set_livery (cmdarg().getPath(), 
#          "Models/livery_nodamage.png", 
#          "Models/livery_slightdamage.png", 
#          "Models/livery_highdamage.png");




####################################################
#timer function, every 1.5 to 2.5 seconds, adds damage if on fire
var fire_loop = func(id, myNodeName) {
	id == loopid or return;
	if(getprop(""~myNodeName~"/effects/general-fire/trigger")) 
		update_fire_params(myNodeName);
  
  # add rand() so that all objects don't do this function simultaneously 
	settimer(func { fire_loop(id, myNodeName); }, 1.5 + rand());
}

###################################################
#timer function, every 0.5 to 1.5 seconds, to keep object at ground level and at reasonable-look pitch
var ground_loop = func(id, myNodeName, altadd, oldalt) {
	id == loopid or return;
	
  #bhugh, update altitude to keep moving objects at ground level the ground	
	var lat = getprop(""~myNodeName~"/position/latitude-deg");
  var lon = getprop(""~myNodeName~"/position/longitude-deg");
  var info = geodinfo(lat, lon);
  
  #set the pitch angle of the object to (approx.) match the slope.
  #since we don't know exactly how long it has been since the last movement
  #or how far we have traveled this is a bit of a guess
  var alt=info[0];
  if (alt==nil) alt=0;
 
  var pitchmult=getprop ( ""~myNodeName~"/controls/constants/pitch-mult");
  var airspeed=getprop ( ""~myNodeName~"/velocities/true-airspeed-kt");
  if (airspeed == 0 or airspeed==nil) airspeed=1; #lets avoid div by zero
  var pitchangle=(alt-oldalt) * pitchmult * 6/airspeed; #we calibrated this to airspeed = 6 kts
  
  
  var oldpitchangle=getprop ( ""~myNodeName~"/orientation/pitch-deg");
  if (oldpitchangle==nil) oldpitchangle=0;
  var diff=pitchangle-oldpitchangle;
  if (abs(diff)>6) {
    if(diff>0) pitchangle=oldpitchangle + 6;
    else pitchangle=oldpitchangle -6;
  }
  #objects seem to sink into the hillside when climbing a hill.  Correction for that, adding a little more when going up (pitchangle>0):
  var altaddmult=getprop ( ""~myNodeName~"/controls/constants/altadd-mult");
  var pitchaltadd=0;
  if  ( pitchangle > 0 ) pitchaltadd = pitchaltadd + pitchangle * altaddmult;
  if ( pitchaltadd > 7) pitchaltadd=7; # more than 10 feet above ground we'll have the opposite problem
  
  setprop (""~myNodeName~"/orientation/pitch-deg", pitchangle );
          
  setprop (""~myNodeName~"/controls/flight/target-alt", alt/0.3048 + altadd+pitchaltadd);
  setprop (""~myNodeName~"/position/altitude-ft", alt/0.3048 + altadd + pitchaltadd);
  
  # add rand() so that all objects don't do this function simultaneously 
	settimer(func { ground_loop(id, myNodeName, alt); }, 0.5 + rand());
}



#######################################################
#location-check loop, a timer function, every 15-16 seconds to check if the object has been relocated (this will happen if the object is set up as an AI ship or aircraft and FG is reset).  If so it restores the object to its position before the reset.
#This solves an annoying problem in FG, where using file/reset (which
#you might do if you crash the aircraft, but also if you run out of ammo
#and need to re-load or for other reasons) will also reset the objects to 
#their original positions.
#With moving objects (set up as AI ships or aircraft with velocities, 
#rudders, and/or flight plans) the objects are often just getting to 
#interesting/difficult positions, so we want to preserve those positions 
# rather than letting them reset back to where they started.
#TODO: Some of this could be done better using a listener on /sim/signals/reinit
var location_loop = func(id, myNodeName) {
	id == loopid or return;
	
	var node = props.globals.getNode(myNodeName);
	
	
	var started = getprop (""~myNodeName~"/position/previous/initialized");
	
  var lat = getprop(""~myNodeName~"/position/latitude-deg");
  var lon = getprop(""~myNodeName~"/position/longitude-deg");
  var alt = getprop(""~myNodeName~"/position/altitude-ft");
  #getting the global_x,y,z seems to stop strange behavior from the smoke
  #when we do a relocate of the objects
  var global_x = getprop(""~myNodeName~"/position/global-x");
  var global_y = getprop(""~myNodeName~"/position/global-y");
  var global_z = getprop(""~myNodeName~"/position/global-z");
        
  
  prev_distance=0;
  directDistance=200; # this will be set as previous/distance if we are initializing
 
  # if we have previously recorded the position we check if it has moved too far
  # if it has moved too far it is because FG has reset and we 
  # then restore the object's position to where it was before the reset
	if (started ) {
     
     var prevlat = getprop(""~myNodeName~"/position/previous/latitude-deg");
     var prevlon = getprop(""~myNodeName~"/position/previous/longitude-deg");
     var prevalt = getprop(""~myNodeName~"/position/previous/altitude-ft");
     var prev_global_x = getprop(""~myNodeName~"/position/previous/global-x");
     var prev_global_y = getprop(""~myNodeName~"/position/previous/global-y");
     var prev_global_z = getprop(""~myNodeName~"/position/previous/global-z");
 
     
     var prev_distance = getprop(""~myNodeName~"/position/previous/distance");
     
     var GeoCoord = geo.Coord.new();
     GeoCoord.set_latlon(lat, lon, alt * 0.3048);

     var GeoCoordprev = geo.Coord.new();
     GeoCoordprev.set_latlon(prevlat, prevlon, prevalt * 0.3048);

     var directDistance = GeoCoord.distance_to(GeoCoordprev);
     
     #print ("Object  ", myNodeName ", distance: ", directDistance);
     
     #4X the previously traveled distance is our cutoff
     #so if our object is moving faster/further than this we assume it has
     #been reset by FG and put it back where it was before the reset.
     #Luckily, this same scheme works in the case this subroutine has moved the 
     #object--then the previous distance exactly equals the distance traveled--
     #so even though that is a much larger than usual distance (which would
     #usually trigger this subroutine to think an init had happened) since
     #the object moved that large distance on the **previous step** (due to the
     #reset) the move back is less than 4X the previous move and so it is OK.

     #A bit kludgy . . . but it works.
     if ( directDistance > 5 and directDistance > 4 * prev_distance ) {
       node.getNode("position/latitude-deg", 1).setDoubleValue(prevlat);
       node.getNode("position/longitude-deg", 1).setDoubleValue(prevlon);
       node.getNode("position/altitude-ft", 1).setDoubleValue(prevalt);
       #now we want to show the previous location as this newly relocated position and distance traveled = 0;
       lat=prevlat;
       lon=prevlon;
       alt=prevalt;
       
 
       print ("Repositioned object ", myNodeName, " to lat: ", prevlat, " long: ", prevlon, " altitude: ", prevalt," ft.");
     }
  }  
  #now we save the current position 
  node.getNode("position/previous/initialized", 1).setBoolValue(1);
  node.getNode("position/previous/latitude-deg", 1).setDoubleValue(lat);
  node.getNode("position/previous/longitude-deg", 1).setDoubleValue(lon);
  node.getNode("position/previous/altitude-ft", 1).setDoubleValue(alt);
  node.getNode("position/previous/global-x", 1).setDoubleValue(global_x);
  node.getNode("position/previous/global-y", 1).setDoubleValue(global_y);
  node.getNode("position/previous/global-z", 1).setDoubleValue(global_z);   
 
  node.getNode("position/previous/distance", 1).setDoubleValue(directDistance);

  # reset the timer so we will check this again in 15 seconds +/-
  # add rand() so that all objects don't do this function simultaneously
  # when 15-20 objects are all doing this simultaneously it can lead to jerkiness in FG 
  settimer(func {location_loop(id, myNodeName); }, 15 + rand());
}


################################################
#listener function on ballistic impacts
#checks if the impact has hit our object and if so, addes the damage

var bombable_test_impact = func(myNodeName) {
	
	var impactNodeName = props.globals.getNode("ai/models/model-impact").getValue();
	var impactNode = props.globals.getNode(impactNodeName);
	var ballisticMass = impactNode.getNode("mass-slug").getValue() * 32.174049; #in lbs
	
	# ignore smoke etc.
	if (ballisticMass<0.26) return;
	
  var impactTerrain = impactNode.getNode("impact/type").getValue();
	
	var node = props.globals.getNode(myNodeName);
	# update object position
	var objectGeoCoord = geo.Coord.new();
	objectGeoCoord.set_latlon(node.getNode("position/latitude-deg").getValue(), node.getNode("position/longitude-deg").getValue(), (node.getNode("position/altitude-ft").getValue()*0.3048));
	var impactGeoCoord = geo.Coord.new();
	impactGeoCoord.set_latlon(impactNode.getNode("impact/latitude-deg").getValue(), impactNode.getNode("impact/longitude-deg").getValue(), impactNode.getNode("impact/elevation-m").getValue());
	var impactDistance = objectGeoCoord.direct_distance_to(impactGeoCoord);
  var impactSurfaceDistance = objectGeoCoord.distance_to(impactGeoCoord);
	var heightDifference=math.abs(impactNode.getNode("impact/elevation-m").getValue() - node.getNode("position/altitude-ft").getValue()*0.3048);
  
  #ignore anything more than 200 meters distant
  if (impactDistance > 200 ) return;
  
	
	#upping impact distance to 6.0 from 4.0, because it seems to ignore
	#legitimate hits at times.  added surface/height distance to make it more forgiving if the impact registers close to the object horizontally but above or below, which seems to happen a lot. bhugh 8/2009.
	if(((impactDistance <= 6.0) or (impactSurfaceDistance <= 4.0 and heightDifference <= 10.0 )) and (impactTerrain != "terrain")) {
		# case of a direct impact, TODO: damage depend on mass and speed of the ballistic
		if(ballisticMass < 0.8) {
			# light bullet
			add_damage(0.05, myNodeName);
		} elsif((ballisticMass >= 0.8) and  (ballisticMass < 1.2)) {
			# such be a big gun, like the GAU-8 gatling gun.
			add_damage(0.8, myNodeName);
		} else {
			# object is surely dead
			add_damage(1.0, myNodeName);
		}
	} else {
		# check submodel blast effect distance.
		if((ballisticMass >= 200) and (ballisticMass < 350)) {
			# Mk-81 class
			if(impactDistance <= 10)
				add_damage(1.0, myNodeName);
			elsif((impactDistance > 10) and (impactDistance < 30))
				add_damage(0.2, myNodeName);
		} elsif((ballisticMass >= 350) and (ballisticMass < 750)) {
			# Mk-82 class
			if(impactDistance <= 33)
				add_damage(1.0, myNodeName);
			elsif((impactDistance > 33) and (impactDistance < 50))
				add_damage(0.25, myNodeName);
		} elsif(ballisticMass >= 750) {
			# Mk-83 class and upper
			if(impactDistance <= 70)
				add_damage(1.0, myNodeName);
			elsif((impactDistance > 70) and (impactDistance < 200))
				add_damage(0.25, myNodeName);
		}
	}
}

################################################################
#function adds damage (called by the fire loop and ballistic impact
#listener function, typically)
var add_damage = func(damageRise, myNodeName) {

  var damageValue = getprop(""~myNodeName~"/effects/damage");
  #for moving objects (ships), reduce velocity each time damage added
	#eventually stopping when damage = 1.  bhugh 8/2009
	#we put it here outside the "if" statement so that burning
	#objects continue to slow/stop even if there damage is already at 1
	# (this happens when file/reset is chosen in FG)
	setprop(""~myNodeName~"/controls/tgt-speed-kts", 
     getprop (""~myNodeName~"/controls/tgt-speed-kts") 
     * (1 - damageValue));
	setprop(""~myNodeName~"/velocities/true-airspeed-kt", 
     getprop (""~myNodeName~"/velocities/true-airspeed-kt") 
     * (1 - damageValue));				
  
  # update effects/damage: 0.0 mean no damage, 1.0 mean full damage
  
	if(damageValue < 1.0) {
		damageValue += damageRise;
		if(damageValue > 1.0)
			damageValue = 1.0;
		elsif(damageValue < 0.0)
			damageValue = 0.0;
		setprop(""~myNodeName~"/effects/damage", damageValue);
		
		
		# start fire if there is enough damages.
		if((damageValue >= 0.75) and !getprop(""~myNodeName~"/effects/general-fire/trigger"))
			setprop(""~myNodeName~"/effects/general-fire/trigger", 1);

    
    # Change livery according to the damage level
		if((damageValue >= 0.15) and (damageValue < 1.0))
	  	setprop(""~myNodeName~"/effects/texture-corps-path", 
         getprop(""~myNodeName~"/effects/color2") );
		elsif(damageValue == 1.0) {
			setprop(""~myNodeName~"/effects/texture-corps-path" , 
           getprop(""~myNodeName~"/effects/color3") );
			# Stop fire and smoke after 60 minutes.
			settimer(func { setprop(""~myNodeName~"/effects/general-fire/trigger", 0); }, 3600);
		}
	}
}

#################################################
var update_fire_params = func(myNodeName) {
	# random end smoke size, between 50 and 150.
	var smokeEndsize = rand();
	smokeEndsize = smokeEndsize*100;
	smokeEndsize += 50;
	setprop(""~myNodeName~"/effects/general-fire/smoke-endsize", smokeEndsize);
	# The object is burning, so we regularly add damage.
	add_damage(0.005, myNodeName);
}

####################################################
#functions to increment loopids
#these are called on init and destruct (which should be called
#when the object loads/unloads)
#When the loopid increments it will kill any timer functions
#using that loopid for that object.  (Otherwise they will just
#continue to run indefinitely even though the object itself is unloaded)
var inc_bomb_loopid = func (nodeName) {
	var loopid = getprop(""~nodeName~"/effects/bomb-loopid"); 
	if ( loopid == nil ) bomb_loopid=0;
	loopid += 1;
	setprop(""~nodeName~"/effects/bomb-loopid", loopid);
	return loopid;
}

var inc_ground_loopid = func (nodeName) {
	var loopid = getprop(""~nodeName~"/effects/ground-loopid"); 
	if ( loopid == nil ) loopid=0;
	loopid += 1;
	setprop(""~nodeName~"/effects/ground-loopid", loopid);
	return loopid;
}

var inc_location_loopid = func (nodeName) {
	var loopid = getprop(""~nodeName~"/effects/location-loopid"); 
	if ( loopid == nil ) loopid=0;
	loopid += 1;
	setprop(""~nodeName~"/effects/location-loopid", loopid);
	return loopid;
}


#####################################################
# Set livery color (including slightly and completely damaged)
# Example:
#
#      set_livery (cmdarg().getPath(), 
#          "Models/livery_nodamage.png", 
#          "Models/livery_slightdamage.png", 
#          "Models/livery_highdamage.png");

var set_livery (nodeName, color1, color2, color3) {
  var node = props.globals.getNode(nodeName);
  
  #colors to use for no/light/full damage
	node.getNode("effects/color1", 1).setValue(color1);
	node.getNode("effects/color2", 1).setValue(color2);
	node.getNode("effects/color3", 1).setValue(color3);
	
	#current color (we'll set it to the undamaged color;
  #if the object is on fire/damage damaged this will soon be updated)
  #by the timer function
	node.getNode("effects/texture-corps-path", 1).setValue(color1);

}
 
#####################################################
#call to initialize an object and make it bombable
#node name can be found using cmdarg().getPath();
#typical usage:
#<PropertyList>
#...
# <nasal>
#...
#  <load>
#      id = bombable_init (cmdarg().getPath(), 
#          "Models/livery_nodamage.png", 
#          "Models/livery_slightdamage.png", 
#          "Models/livery_highdamage.png");
#  </load>
#  <unload>
        bombable_del( cmdarg().getPath(), id );
#  </unload>
# </nasal>  
#</PropertyList>

var bombable_init = func(nodeName, color1, color2, color3) {
	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	loopid=inc_bomb_loopid(nodeName);
	
  var node = props.globals.getNode(nodeName);
	# Add some useful nodes


	node.getNode("effects/general-fire/smoke-endsize", 1).setDoubleValue(50.0);
	node.getNode("effects/general-fire/trigger", 1).setBoolValue(0);
	node.getNode("effects/damage", 1).setDoubleValue(0.0);
	
	#set the livery for no damage, slight damage, full damage
  set_livery (nodeName, color1, color2, color3);		
	
	
  #set the listener to check for impact damage				
	listenerid = setlistener("ai/models/model-impact", func { bombable_test_impact(nodeName); });
	
	#start the loop to check for fire damage
	settimer(func { bombable_loop(loopid, nodeName); }, 5.0+rand());
	
	print ("Effect 'bombable' loaded for ", nodeName, " loopid=", loopid);
	
	return listenerid;
}

#####################################################
# Call to make your object stay on the ground--like a jeep or tank that
# drives along the ground.  The altitide will be continually readjusted
# as the object (set up as, say, and AI ship or aircraft moves.
# In addition the pitch will change to (roughly) match when going up
# or downhill.
# Variable "altadjust" is the distance in feet to add to your object's
# altitude--lets you adjust to keep your vehicle just on the ground,
# your ship riding just below the water level, etc.
# Put this nasal code in your object's load:
#      altadjust=3; #distance, in feet, to add to your object's altitude
#      ground_init (cmdarg().getPath(), altadjust);
var ground_init = func(nodeName, altadjust) {
				
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	loopid=inc_ground_loopid(nodeName);
	
  var node = props.globals.getNode(nodeName);

	# Add some useful nodes
	
	# multiplier to determine object's pitch depending on altitude change
	# these can be adjusted to control the object's pitch when on hills
	# and the altitude adjustment when descending hills
  node.getNode("controls/constants/pitch-mult", 1).setDoubleValue(18);		
	
	node.getNode("controls/constants/altadd-mult", 1).setDoubleValue(0.2);
  #get the object's initial altitude
	var lat = getprop(""~nodeName~"/position/latitude-deg");
  var lon = getprop(""~nodeName~"/position/longitude-deg");
  var info = geodinfo(lat, lon);
  var alt=info[0];
  
  #initialize the timer loop to keep the altitude adjusted
	settimer(func { ground_loop(loopid, nodeName, altadjust, alt); }, 4.0 + rand();
	
	print ("Effect 'drive on ground' loaded for ", nodeName, "altitude adjustment=",altadjust, loopid=", loopid);

	
}

#####################################################
# Call to make your object keep its location even after a re-init
# (file/reset).  For instance a fleet of tanks, cars, or ships
# will keep its position after the reset rather than returning
# to their initial position.'
#
# Put this nasal code in your object's load:
#      location_init (cmdarg().getPath())

var location_init = func(nodeName) {
	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	loopid=inc_location_loopid(nodeName);
	
  var node = props.globals.getNode(nodeName);

	
	settimer(func { location_loop(loopid, nodeName); }, 15.0 + rand();

  print ("Effect 'relocate after reset' loaded for ", nodeName, " loopid=", loopid);

}


#####################################################
#unload function (delete/destructor) for bombable_init
#
#typical usage:
#<PropertyList>
#...
# <nasal>
#...
#  <unload>
#      bombable_del (cmdarg().getPath(), id);
#  </unload
# </nasal>  
#</PropertyList>

var bombable_del = func(nodeName, id) {
	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	loopid=inc_bomb_loopid(nodeName);
	
	
  #set the listener to check for impact damage				
	listenerid = removelistener(id);
	
	#start the loop to check for fire damage
	settimer(func { bombable_loop(loopid, nodeName); }, 5.0+rand());
	
	print ("Effect 'bombable' unloaded for ", nodeName, " loopid=", loopid);
	

}

#####################################################
# del/destructor function for ground_init
# Put this nasal code in your object's unload:
#      bombable_del (cmdarg().getPath());
var ground_del = func(nodeName) {
				
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	loopid=inc_ground_loopid(nodeName);
	
	print ("Effect 'drive on ground' unloaded for ", nodeName, " loopid=", loopid);

	
}

#####################################################
# del/destructor for location_init
# Put this nasal code in your object's unload:
#      location_del (cmdarg().getPath());

var location_del = func(nodeName) {
	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	loopid=inc_location_loopid(nodeName);
	

  print ("Effect 'relocate after reset' unloaded for ", nodeName, " loopid=", loopid);

}