#####################################################
## Bombable
## Brent Hugh, brent@brenthugh.com
var bombableVersion = "4.5";
## 
## Copyright (C) 2009 - 2011  Brent Hugh  (brent@brenthugh.com)
## This file is licensed under the GPL license version 2 or later.
# 
# The Bombable module implements several different but interrelated functions
# that can be used by, for example, AI objects and scenery objects.  The 
# functions allow shooting and bombing of AI and multiplayer objects, explosions 
# and disabling of objects that are hit, and even multiplayer communications to 
# allow dogfighting:
#
# 1. BOMBABLE: Makes objects bombable.  They will detect hits, change livery according to damage, and finally start on fire and smoke when sufficiently damaged. There is also a function to change the livery colors according to damage level.
# 
# Bombable also works for multiplayer objects and allows multiplayer dogfighting.
# 
# In addition, it creates an explosion whenever the main aircraft hits the ground and crashes.
#
# 2. GROUND: Makes objects stay at ground level, adjusting pitch to match any slope they are on.  So, for instance, cars, trucks, or tanks can move and always stay on the ground, drive up slopes somewhat realistically, etc. Ships can be placed in any lake and will automatically find their correct altitude, etc.
#
# 3. LOCATE: Usually AI objects return to their initial start positions when FG re-inits (ie, file/reset). This function saves and maintains their previous position prior to the reset
# 
# 4. ATTACK: Makes AI Aircraft (and conceivable, other AI objects as well) swarm and attack the main aircraft
#
# 5. WEAPONS: Makes AI Aircraft shoot at the main aircraft
#
#TYPICAL USAGE--ADDING BOMBABILITY TO AN AI OR SCENERY MODEL
#
# Required: 
#  1. The Fire-Particles subdirectory (included in this package) 
#     must be installed in the FG/data/AI/Aircraft/Fire-Particles subdirectory
#  2. This file, bombable.nas, must be installed in the FG/data/Nasal 
#     subdirectory
# 
# To make any particular object "bombable", simply include code similar to that 
# included in the AI aircraft XML files in this distribution.
# 
# This approach generally should work with any AI objects or scenery objects.
# 
# You then typically create an AI scenario that includes these "bombable 
# objects" and then, to see and bomb the objects, load the scenario using
# the command line or fgrun when you start FlightGear. 
# 
# Or two (or more) players can choose aircraft set up for dogfighting (see readme in accompanying documentation) and dogfight via multiplayer.  Damage, smoke, fire, and explosions are all transmitted via multiplayer channels.
# 
# Notes:
#  - The object's node name can be found using cmdarg().getPath()
#  - You can make slight damage & high damage livery quite easily by modifying
#    any existing livery a model may have.  Note, however, that many objects
#    do not use liveries, but simply include color in the model itself. You
#    won't be able to change liveries on such models unless you alter the 
#    model (.ac file) to use external textures. 
#  
# 
# See file bombable-modding-aircraft-for-dogfighting.txt included in this 
# package for more details about adding bombable to aircraft or other objects.
# 
# See m1-abrams/m1.xml and other AI object XML files in this package for 
# sample implementations.
#
#
#AUTHORS
# 	Base code for M1 Abrams tank by Emmanuel BARANGER - David BASTIEN
#   Modded heavily by Brent HUGH to add re-location and ground altitude 
#   functionality, crashes for ships and aircraft, evasive maneuvers when
#   under attack, multiplayer functionality, other functionality, 
#   and to abstract the code to a unit that can be included in most 
#   any AI or scenery object.
# 
#   Many snippets of code and examples of implemention were borrowed from other
#   FlightGear projects--thanks to all those contributors!
# 


#################################
# prints values to console only if 'debug' flag is set in props
var debprint = func {

   setprop ("/sim/startup/terminal-ansi-colors",0);
   
   if (getprop(""~bomb_menu_pp~"debug")) {                                                               
    outputs="";
    foreach (var elem;arg) {
       if (elem != nil) {
         if (typeof(elem)=="scalar") outputs = string.trim(outputs) ~ " " ~ elem; 
         else debug.dump(elem);
       }  
    };
    outputs= outputs ~ " (Line #"; 
    var call1=caller();
    var call2=caller("2");
    var call3=caller ("3");
    var call4=caller ("4");
    if (typeof(call1)=="vector")  outputs = outputs ~ call1["3"] ~ " ";
    if (typeof(call2)=="vector")  outputs = outputs ~ call2["3"] ~ " ";
    if (typeof(call3)=="vector")  outputs = outputs ~ call3["3"] ~ " ";        
    if (typeof(call4)=="vector")  outputs = outputs ~ call4["3"] ~ " ";    
    outputs=outputs ~ ")";
    
    print (outputs);
  }
}


###############################
# returns round to nearest whole number 
var round = func (a ) return int (a+0.5);

###############################
# normalize degree to -180 < angle <= 180
# (for checking aim)
#
var normdeg180 = func(angle) {
	while (angle <= - 180)
		angle += 360;
	while (angle > 180)
		angle -= 360;
	return angle;
}

###########################################################
# Checks whether nodeName has been overall-initialized yet
# if so, returns 1
# if not, returns 0 and sets nodeName ~ /bombable/overall-initialized to true
# 
var check_overall_initialized = func(nodeName) {
      nodeName=cmdarg().getPath();
      #only allow initialization for ai & multiplayer objects
      # in FG 2.4.0 we're having trouble with strange(!?) init requests from
      # joysticks & the like  
      var init_allowed=0;
      if (find ("/ai/models/", nodeName ) != -1 ) init_allowed=1;
      if (find ("/multiplayer/", nodeName ) != -1 ) init_allowed=1;
      
      if (init_allowed!=1) {
       bombable.debprint ("Bombable: Attempt to initialize a Bombable subroutine on an object that is not AI or Multiplayer; aborting initialization. ", nodeName);
       return 1; #1 means abort; it's initialized already or can't/shouldn't be initialized,
      } 
      
      # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
      # if it 1 and we're trying to initialize, something has gone wrong and we abort with a message.  
      var inited= getprop(""~nodeName~"/bombable/overall-initialized");
      
      if (inited==1) {
       bombable.debprint ("Bombable: Attempt to re-initialize AI aircraft when it has not been de-initialized; aborting re-initialization. ", nodeName);
       return 1; #1 means abort; it's initialized already or can't/shouldn't be initialized,
      } 
      # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
      setprop(""~nodeName~"/bombable/overall-initialized", 1);
      return 0;
}

var de_overall_initialize = func(nodeName) {

    setprop(""~nodeName~"/bombable/overall-initialized", 0);

}

var mpprocesssendqueue = func {
 	
  #we do the settimer first so any runtime errors, etc., below, don't stop the
  # future instances of the timer from being started  
  settimer (func {mpprocesssendqueue()}, mpTimeDelaySend );  # This was experimental: mpTimeDelaySend * (97.48 + rand()/20 )
  
  if (!getprop(MP_share_pp)) return "";
  if (!getprop (MP_broadcast_exists_pp)) return "";
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;

  if (size(mpsendqueue) > 0) {
      setprop (MP_message_pp, mpsendqueue[0]);
      mpsendqueue=subvec(mpsendqueue,1); 
  }

}

var mpsend = func (msg) {
   #adding systime to the end of the message ensures that each message is unique--otherwise messages that happen to be the same twice in a row will 
   # be ignored.  The system() at the end is ignored by the parser.
   #     
   if (!getprop(MP_share_pp)) return "";
   if (!getprop (MP_broadcast_exists_pp)) return "";
   if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;   
    
   append(mpsendqueue, msg~systime());
}

var mpreceive = func (mpMessageNode) {
  
  if (!getprop(MP_share_pp)) return "";
  if (!getprop (MP_broadcast_exists_pp)) return "";
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
    
  msg=mpMessageNode.getValue();    
  mpMessageNodeName=mpMessageNode.getPath();
  mpNodeName=string.replace (mpMessageNodeName, MP_message_pp, "");
  if (msg!=nil and msg !="") {
      debprint("Bombable: Message received from ", mpNodeName,": ", msg);
      parse_msg (mpNodeName, msg);
  }
      
  

}

################################################################################
#put_ballistic_model places a new model that is starts atanother AI model's
# position but moves independently, like a bullet, bomb, etc
# this is still not working/experimental
# #update: The best way to do this appears to be to include a weapons/tracer
# submodel in the main aircraft.  Then have Bombable place
# it in the right location, speed, direction, and trigger it.
# Somewhat similar to: http://wiki.flightgear.org/Howto:_Add_contrails#Persistent_Contrails

var put_ballistic_model = func(myNodeName="/ai/models/aircraft", path="AI/Aircraft/Fire-Particles/fast-particles.xml") {

  #debprint ("Bombable: setprop 149");
  # "environment" means the main aircraft
	#if (myNodeName=="/environment" or myNodeName=="environment") myNodeName="";

  fgcommand("add-model", ballisticNode=props.Node.new({ 
          "path": path, 
          "latitude-deg-prop": myNodeName ~ "/position/latitude-deg", 
          "longitude-deg-prop":myNodeName ~ "/position/longitude-deg", 
          "elevation-ft-prop": myNodeName ~ "/position/altitude-ft", 
          "heading-deg-prop": myNodeName ~ "/orientation/true-heading-deg", 
          "pitch-deg-prop": myNodeName ~ "/orientation/pitch-deg", 
          "roll-deg-prop": myNodeName ~ "/orientation/roll-deg", 
  })); 
  
  
  print (ballisticNode.getName());
  print (ballisticNode.getName().getNode("property").getName());
  print (props.globals.getNode(ballisticNode.getNode("property").getValue()));
  print (ballisticNode.getNode("property").getValue());
  return props.globals.getNode(ballisticNode.getNode("property").getValue());

}

################################################################################
#put_remove_model places a new model at the location specified and then removes
# it time_sec later 
#it puts out 12 models/sec so normally time_sec=.4 or thereabouts it plenty of time to let it run
# If time_sec is too short then no particles will be emitted.  Typical problem is 
# many rounds from a gun slow FG's framerate to a crawl just as it is time to emit the 
# particles.  If time_sec is slower than the frame length then you get zero particle.
# Smallest safe value for time_sec is maybe .3 .4 or .5 seconds.
# 
var put_remove_model = func(lat_deg=nil, lon_deg=nil, elev_m=nil, time_sec=nil, startSize_m=nil, endSize_m=1, path="AI/Aircraft/Fire-Particles/flack-impact.xml" ) {

  if (lat_deg==nil or lon_deg==nil or elev_m==nil) { return; } 
 
  var delay_sec=0.1; #particles/models seem to cause FG crash *sometimes* when appearing within a model
  #we try to reduce this by making the smoke appear a fraction of a second later, after
  # the a/c model has moved out of the way. (possibly moved, anyway--depending on it's speed)  

  debprint ("Bombable: Placing flack");
         
  settimer ( func {
    #start & end size in particle system appear to be in feet
    if (startSize_m!=nil) setprop ("/bombable/fire-particles/flack-startsize", startSize_m);
    if (endSize_m!=nil) setprop ("/bombable/fire-particles/flack-endsize", endSize_m);

    fgcommand("add-model", flackNode=props.Node.new({ 
            "path": path, 
            "latitude-deg": lat_deg, 
            "longitude-deg":lon_deg, 
            "elevation-ft": elev_m/feet2meters,
            "heading-deg"  : 0,
            "pitch-deg"    : 0,
            "roll-deg"     : 0, 
            "enable-hot"   : 0,
  
            
              
    }));
    
  var flackModelNodeName= flackNode.getNode("property").getValue();
  
  #add the -prop property in /models/model[X] for each of lat, long, elev, etc
  foreach (name; ["latitude-deg","longitude-deg","elevation-ft", "heading-deg", "pitch-deg", "roll-deg"]){
   setprop(  flackModelNodeName ~"/"~ name ~ "-prop",flackModelNodeName ~ "/" ~ name );
  }  
  
  debprint ("Bombable: Placed flack, ", flackModelNodeName);
  
  settimer ( func { props.globals.getNode(flackModelNodeName).remove();}, time_sec);

  }, delay_sec);   

}

##############################################################
#Start a fire on terrain, size depending on ballisticMass_lb
#location at lat/lon
#
var start_terrain_fire = func ( lat_deg, lon_deg, alt_m=0, ballisticMass_lb=1.2 ) {

  var info = geodinfo(lat_deg, lon_deg);
   
  
  
  debprint ("Bombable: Starting terrain fire at ", lat_deg, " ", lon_deg, " ", alt_m, " ", ballisticMass_lb);
  
  #get the altitude of the terrain
  if (info != nil) {
      #debprint ("Bombable: Starting terrain fire at ", lat_deg, " ", lon_deg, " ", info[0]," ", info[1].solid );
      
      #if it's water we don't set a fire . . . TODO make a different explosion or fire effect for water 
      if (typeof(info[1])=="hash" and contains(info[1], "solid") and info[1].solid==0) return;
      else debprint (info);
      
      #we go with explosion point if possible, otherwise the height of terrain at this point
      if (alt_m==nil) alt_m=info[0];
      if (alt_m==nil) alt_m=0; 
      
  }
  
    if (ballisticMass_lb==nil or ballisticMass_lb<0) ballisticMass_lb=1.2;
    if (ballisticMass_lb < 3 ) { time_sec=20; fp="AI/Aircraft/Fire-Particles/fire-particles-very-very-small.xml"; }
    elsif (ballisticMass_lb < 20 ) { time_sec=60; fp="AI/Aircraft/Fire-Particles/fire-particles-very-very-small.xml"; }
		elsif (ballisticMass_lb < 50 ) { time_sec=120; fp="AI/Aircraft/Fire-Particles/fire-particles-very-small.xml"; }
			elsif (ballisticMass_lb > 450 ) {time_sec=600; fp="AI/Aircraft/Fire-Particles/fire-particles.xml"; }
			elsif (ballisticMass_lb > 1000 ) { time_sec=900; fp="AI/Aircraft/Fire-Particles/fire-particles-large.xml"; }
			else {time_sec=300; fp="AI/Aircraft/Fire-Particles/fire-particles-small.xml";} 

  debprint ({lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m, time_sec:time_sec, startSize_m: nil, endSize_m:nil, path:fp });
  put_remove_model(lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m, time_sec:time_sec, startSize_m: nil, endSize_m:nil, path:fp );
  
  #making the fire bigger for bigger bombs
  if (ballisticMass_lb >= 1000 ) put_remove_model(lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m+1, time_sec:time_sec*.9, startSize_m: nil, endSize_m:nil, path:fp );
  if (ballisticMass_lb >= 1500 ) put_remove_model(lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m+2, time_sec:time_sec*.8, startSize_m: nil, endSize_m:nil, path:fp );
  if (ballisticMass_lb >= 2000 ) put_remove_model(lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m+3, time_sec:time_sec*.7, startSize_m: nil, endSize_m:nil, path:fp );  
  
  ##put it out, but slowly, for large impacts
  if (ballisticMass_lb>50) {
    time_sec2=120; fp2="AI/Aircraft/Fire-Particles/fire-particles-very-small.xml";  
    settimer (func { put_remove_model(lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m, time_sec:time_sec2, startSize_m: nil, endSize_m:nil, path:fp2 )} , time_sec);
    
    time_sec3=120; fp3="AI/Aircraft/Fire-Particles/fire-particles-very-very-small.xml";  
    settimer (func { put_remove_model(lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m, time_sec:time_sec3, startSize_m: nil, endSize_m:nil, path:fp3 )} , time_sec+time_sec2);
    
    time_sec4=120; fp4="AI/Aircraft/Fire-Particles/fire-particles-very-very-very-small.xml";  
    settimer (func { put_remove_model(lat_deg:lat_deg, lon_deg:lon_deg, elev_m:alt_m, time_sec:time_sec4, startSize_m: nil, endSize_m:nil, path:fp4 )} , time_sec+time_sec2+time_sec3);
  
  }

}



################################################################################
#put_tied_model places a new model that is tied to another AI model 
# (given by myNodeName) and will move with it in lon, lat, & alt

var put_tied_model = func(myNodeName="", path="AI/Aircraft/Fire-Particles/Fire-Particles.xml ") {

  #debprint ("Bombable: setprop 174"); 
  # "environment" means the main aircraft
	#if (myNodeName=="/environment" or myNodeName=="environment") myNodeName="";

  fgcommand("add-model", fireNode=props.Node.new({ 
          "path": path, 
          "latitude-deg-prop": myNodeName ~ "/position/latitude-deg", 
          "longitude-deg-prop":myNodeName ~ "/position/longitude-deg", 
          "elevation-ft-prop": myNodeName ~ "/position/altitude-ft", 
          "heading-deg-prop": myNodeName ~ "/orientation/true-heading-deg", 
          "pitch-deg-prop": myNodeName ~ "/orientation/pitch-deg", 
          "roll-deg-prop": myNodeName ~ "/orientation/roll-deg", 
  })); 
  
  return props.globals.getNode(fireNode.getNode("property").getValue());

}

################################################################################
#put_tied_weapon places a new model that is tied to another AI model 
# (given by myNodeName) and will move with it in lon, lat, & alt
# and have the delta heading, pitch, lat, long, alt, as specified in weapons_init
# 

var put_tied_weapon = func(myNodeName="", elem="", startSize_m=.07, endSize_m=.05, path="AI/Aircraft/Fire-Particles/Fire-Particles.xml ") {

  #debprint ("Bombable: setprop 174"); 
  # "environment" means the main aircraft
	#if (myNodeName=="/environment" or myNodeName=="environment") myNodeName="";

  if (startSize_m!=nil) setprop ("/bombable/fire-particles/projectile-startsize", startSize_m);
  if (endSize_m!=nil) setprop ("/bombable/fire-particles/projectile-endsize", endSize_m);


  fgcommand("add-model", fireNode=props.Node.new({ 
          "path": path, 
          "latitude-deg-prop": myNodeName ~ "/" ~ elem ~ "/position/latitude-deg", 
          "longitude-deg-prop":myNodeName ~ "/" ~ elem ~ "/position/longitude-deg", 
          "elevation-ft-prop": myNodeName ~ "/" ~ elem ~ "/position/altitude-ft", 
          "heading-deg-prop": myNodeName ~ "/" ~ elem ~ "/orientation/true-heading-deg", 
          "pitch-deg-prop": myNodeName ~ "/" ~ elem ~ "/orientation/pitch-deg", 
          "roll-deg-prop": myNodeName ~ "/" ~ elem ~"/orientation/roll-deg", 
  })); 
  
  return props.globals.getNode(fireNode.getNode("property").getValue());

}



####################################################
#Delete a fire object (model) created earlier, turn off the fire triggers
#and unlink the fire from the parent object.
#This sets the object up so it can actually start on fire again if 
#wanted (or hit again by ballistics . . . though damage is already to max if 
#it has been on fire for a while, and damage is not re-set)
var deleteFire = func (myNodeName="",fireNode="") {

    #if (myNodeName=="") myNodeName="/environment";
    if (fireNode=="") {
        fireNodeName=getprop(""~myNodeName~"/bombable/fire-particles/fire-particles-model");
        if (fireNodeName==nil) return;
        fireNode = props.globals.getNode(fireNodeName);
    }
        
    #remove the fire node/model altogether
    if (fireNode!= nil) fireNode.remove();
    
    #turn off the object's fire trigger & unlink it from its fire model
    setprop(""~myNodeName~"/bombable/fire-particles/fire-burning", 0);
    setprop(""~myNodeName~"/bombable/fire-particles/fire-particles-model", "");

}

####################################################
#Check current speed & add damage due to excessive speed
#
var speedDamage = func {

    if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
    var damage_enabled=getprop (""~GF_damage_menu_pp~"damage_enabled");
    var warning_enabled=getprop (""~GF_damage_menu_pp~"warning_enabled");
    
    if (!  damage_enabled and ! warning_enabled ) return;
    
      var currSpeed_kt=getprop("/velocities/airspeed-kt");
      if (currSpeed_kt==0 or currSpeed_kt == nil) return; 
      
      var speedDamageThreshold_kt = getprop(""~vulnerabilities_pp~"airspeed_damage/damage_threshold_kt/");
      var speedWarningThreshold_kt = getprop(""~vulnerabilities_pp~"airspeed_damage/warning_threshold_kt/");
      
      if (speedDamageThreshold_kt==0 or speedDamageThreshold_kt==nil) speedDamageThreshold_kt=7000;
      if (speedWarningThreshold_kt==0 or speedWarningThreshold_kt==nil) speedWarningThreshold_kt=7000;
       
      var speedDamageMultiplier_PercentPerSecond = getprop(""~vulnerabilities_pp~"airspeed_damage/damage_multiplier_percentpersecond/");
      
      if (speedDamageMultiplier_PercentPerSecond==nil) speedDamageMultiplier_PercentPerSecond=1;
      
      #debprint ("Bombable: Speed checking ", currSpeed_kt, " ", speedDamageThreshold_kt, " ", speedWarningThreshold_kt," ", speedDamageMultiplier_PercentPerSecond);

      if (warning_enabled and currSpeed_kt > speedWarningThreshold_kt ) {
          var msg="Overspeed warning: "~ round ( currSpeed_kt ) ~" kts";
          debprint(msg);
          #only put the message on the screen if damage is less than 100%
          # after that there is little point AND it will overwrite
          # any "you're out of commission" message                              
          if ( getprop("/bombable/attributes/damage") <1) 
            selfStatusPopupTip (msg, 5 );
      }

      if (damage_enabled and currSpeed_kt > speedDamageThreshold_kt ) {
          mainAC_add_damage( speedDamageMultiplier_PercentPerSecond * (currSpeed_kt -speedDamageThreshold_kt)/100,
          0, "speed", "" ~ round( currSpeed_kt ) ~ " kts (overspeed) damaged airframe!" );
        
      }
    

}


####################################################
#Check current accelerations & add damage due to excessive acceleration
#
var accelerationDamage = func {

    var damage_enabled=getprop (""~GF_damage_menu_pp~"damage_enabled");
    var warning_enabled=getprop (""~GF_damage_menu_pp~"warning_enabled");
    
    if (! damage_enabled and ! warning_enabled ) return;
    if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
    
    #debprint ("Bombable: Checking acceleration");
    #The acceleration nodes are updated once per second
    
    
      var currAccel_g=getprop("/accelerations/pilot-gdamped");
      if (currAccel_g==0 or currAccel_g == nil) return;
      
      if (currAccel_g>0 ) a="positive";
      else a="negative";
       
      currAccel_fg=math.abs(currAccel_g);
      
      
      var accelDamageThreshold_g = getprop(""~GF_damage_pp~"damage_threshold_g/"~a);
      var accelWarningThreshold_g = getprop(""~GF_damage_pp~"warning_threshold_g/"~a);
      
      if (accelDamageThreshold_g==0 or accelDamageThreshold_g==nil) accelDamageThreshold_g=50;
      if (accelWarningThreshold_g==0 or accelWarningThreshold_g==nil) accelWarningThreshold_g=10;
       
      var accelDamageMultiplier_PercentPerSecond = getprop(""~GF_damage_pp~"damage_multiplier_percentpersecond/"~a);
      
      if (accelDamageMultiplier_PercentPerSecond==nil) accelDamageMultiplier_PercentPerSecond=8;
      
      #debprint ("Bombable: Accel checking ", a, " ", currAccel_g, " ", accelDamageThreshold_g, " ", accelWarningThreshold_g," ", accelDamageMultiplier_PercentPerSecond);

      if (warning_enabled and currAccel_g > accelWarningThreshold_g ) {
          var msg="G-force warning: "~ round( currAccel_g ) ~"g";
          debprint(msg);
          #only put the message on the screen if damage is less than 100%
          # after that there is little point AND it will overwrite
          # any "you're out of commission" message                              
          if ( getprop("/bombable/attributes/damage") <1) 
            selfStatusPopupTip (msg, 5 );
      }

      if (damage_enabled and currAccel_g > accelDamageThreshold_g ) {
          mainAC_add_damage( accelDamageMultiplier_PercentPerSecond * (currAccel_g -accelDamageThreshold_g)/100,
          0, "gforce", "" ~ sprintf("%1.2f", currAccel_g*10 ) ~ "g force damaged airframe!" );
        
      }
}

#########################################################################
# timer for accel  & speed damage checks
# 
var damageCheck = func () {
  settimer (func {damageCheck (); }, damageCheckTime);
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
  #debprint ("Bombable: Checking damage.");
  accelerationDamage();
  speedDamage();

}

    #Notes on g-force:
  	# Max G tolerated by a person for periods of c. 1 sec or more 
  	# is about 30-50g even in fairly ideal circumstances.  So even if the aircraft
  	# survives your 30+g maneuver--you won't!  
  	# F22 has max g of 9.5 and Su-47 has max g of 9, so those numbers
  	# are probably pretty typical for modern fighter jets.    	
  	# See http://www.thespacereview.com/article/410/1  	
  	# http://www.airforce-technology.com/projects/s37/
  	# http://www.airforce-technology.com/projects/s37/  	
  	# Max G tolerated routinely by fighter or acrobatic
  	#   pilots etc seems to be about 9-12g
  	# 12-17g is tolerated long term, depending on the direction of the 
  	# acceleration  See http://en.wikipedia.org/wiki/G-force
  	# #max g for WWI era aircraft was 4-5g (best guess).  Repeat high gs do
    # weaken the structure.
    # In modern aircraft, F-16 has a maximum G of 9, F-18: 9.6, Mirage M.III/V: 7, A-4:6.
    # http://www.ww2aircraft.net/forum/technical/strongest-aircraft-7494-3.html :  
   # WW2 aircraft sometimes has higher max G, but it is interesting because pilot did not have G-suit, and trained pilots could not resist 5g for more than some seconds without G-suit.       
   # the strongest aircraft of WWII were the Italian monoplane fighters. They were built to withstand 8g normal load with 12g failure load. The same spec for German aircraft was 6g - 8.33g. For the late war P51s it was 5.33g
   # Spitfire VIII can pull about 9 and dive to about 570 mph before ripping apart while the F4U will only dive to about 560 mph and pull a similar load. 
   # at normal weight the designed limit load was 7.5 g positive and 3.5 g negative for the Corsair.
   #  FIAT G.50 had an ultimate factor of 14 g. According to Dottore Eng. Gianni Cattaneo´s Profile booklet on the Macchi C.202, it had an ultimate factor of no less than 15.8 g! That would make it virtually indestructible. Also the Hawker Tempest was strong with its 14+ G strength.
   # http://www.aviastar.org/air/japan/mitsubishi_a6m.php : 
   # Most Japanese fighters were designed to withstand a force of 7g. From 1932 all Japanese warplanes were required to meet a safety load factor of 1.8 so the limit for the A6M had to be 12.6g (1.8x7g).      
  

########################################################
#Set attributes for main aircraft
#  You can set vulnerabilities for any aircraft by 
#  simply creating a file 'vulnerabilities.nas',  
#  defining vulsObject as below, and including the line
#      bombable.setAttributes (attsObject);
#  
var setAttributes = func (attsObject=nil) {
  debprint ("Bombable: Loading main aircraft vulnerability settings.");
  if (attsObject==nil) { 
      attsObject = { 
      
          # TODO: Update all below to be actual dimensions of that aircraft
          #########################################
          # DIMENSION DEFINITIONS
          #
          # All dimensions are in meters
          # source: http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II          
          #           
          dimensions : {                  
            width_m : 17.53,  #width of your object, ie, for aircraft, wingspan
            length_m : 16.26, #length of your object, ie, for aircraft, distance nose to tail
            height_m : 4.47, #height of your object, ie, for aircraft ground to highest point when sitting on runway
            
            damageRadius_m : 8, #typically 1/2 the longest dimension of the object. Hits within this distance of the 
                                #center of object have some possibility of damage
            vitalDamageRadius_m : 2, #typically the radius of the fuselage or cockpit or other most 
                                     # vital area at the center of the object.  Always smaller than damageRadius_m
                                    
            crashRadius_m : 6, #It's a crash if the main aircraft hits in this area.
                                
          },

        
        vulnerabilities: {
          engineDamageVulnerability_percent : 3,
          fireVulnerability_percent:15,
          damageVulnerability:20,
          fireExtinguishSuccess_percentage:10,
          fireExtinguishMaxTime_seconds:100,
          fireDamageRate_percentpersecond : .4,
          explosiveMass_kg : 20000,
          airspeed_damage:{
            #If we don't know the aircraft it could be anything, even the UFO.
            damage_threshold_kt: 200000,
            warning_threshold_kt: 8500,
            #1kt over the threshold for 1 second will add 1% damage:
            damage_multiplier_percentpersecond: 0.07
          },   
          gforce_damage: {
            damage_enabled: 0,
            warning_enabled: 1,
            damage_threshold_g: {positive:30, negative:20},
            warning_threshold_g: {positive:12, negative:7},
            #1g over the threshold for 1 second will add 8% damage:
            damage_multiplier_percentpersecond: {positive:8, negative:8 }
          },
          redout: {
            enabled: 0,
            parameters: {
              blackout_onset_g: 4,
              blackout_complete_g: 5,
              redout_onset_g: -2,
              redout_complete_g: -3
            }        
          } 
        }
     }  
   }; 
      
              	
      
      #predefined values for a few aircraft we have set up for
      # dogfighting       
      var aircraftname=getprop("sim/aircraft");
      if (string.match(aircraftname,"A6M2*" )){
        debprint ("Bombable: Loading A6M2 main aircraft vulnerabilities");      
        attsObject = {                                  
      
          #########################################
          # DIMENSION DEFINITIONS
          #
          # All dimensions are in meters
          # source: http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II          
          #           
          dimensions : {                  
            width_m : 17.53,  #width of your object, ie, for aircraft, wingspan
            length_m : 16.26, #length of your object, ie, for aircraft, distance nose to tail
            height_m : 4.47, #height of your object, ie, for aircraft ground to highest point when sitting on runway
            
            damageRadius_m : 8, #typically 1/2 the longest dimension of the object. Hits within this distance of the 
                                #center of object have some possibility of damage
            vitalDamageRadius_m : 2, #typically the radius of the fuselage or cockpit or other most 
                                     # vital area at the center of the object.  Always smaller than damageRadius_m
                                    
            crashRadius_m : 6, #It's a crash if the main aircraft hits in this area.
                                
          },
          
          vulnerabilities: {
            engineDamageVulnerability_percent : 6,
            fireVulnerability_percent:34,
            fireDamageRate_percentpersecond : .4,
            damageVulnerability:90,
            fireExtinguishSuccess_percentage:50,
            fireExtinguishMaxTime_seconds:50,
            explosiveMass_kg : 27772, 
            airspeed_damage:{
              damage_threshold_kt: 356, #http://en.wikipedia.org/wiki/A6M_Zero
              warning_threshold_kt: 325,
              #1 kt over the threshold for 1 second will add 1% damage:
              damage_multiplier_percentpersecond: 0.07
            },
            gforce_damage: {
                damage_enabled: 1,  #boolean yes/no
                warning_enabled: 1, #boolean yes/no
                damage_threshold_g: {positive:12.6, negative:9},
                warning_threshold_g: {positive:7, negative:6},
                damage_multiplier_percentpersecond: {positive:12, negative:12 }
            },
            redout: {
              enabled: 1,
              parameters: {
                blackout_onset_g: 5, #no g-suit in WWI so really 6gs is pushing it
                blackout_complete_g: 7,
                redout_onset_g: -2.5,
                redout_complete_g: -3
              }        
            }  
          }
        }
        
      } elsif ( string.match(aircraftname,"A-10*" ) ) {
          debprint ("Bombable: Loading A-10 main aircraft vulnerabilities");
          attsObject = {
          #########################################
          # DIMENSION DEFINITIONS
          #
          # All dimensions are in meters
          # source: http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II          
          #           
          dimensions : {                  
            width_m : 17.53,  #width of your object, ie, for aircraft, wingspan
            length_m : 16.26, #length of your object, ie, for aircraft, distance nose to tail
            height_m : 4.47, #height of your object, ie, for aircraft ground to highest point when sitting on runway
            
            damageRadius_m : 8, #typically 1/2 the longest dimension of the object. Hits within this distance of the 
                                #center of object have some possibility of damage
            vitalDamageRadius_m : 2, #typically the radius of the fuselage or cockpit or other most 
                                     # vital area at the center of the object.  Always smaller than damageRadius_m
                                    
            crashRadius_m : 6, #It's a crash if the main aircraft hits in this area.
                                
          },
            
            vulnerabilities: {
  
              engineDamageVulnerability_percent : 6,
              fireVulnerability_percent:7,
              fireDamageRate_percentpersecond : .1,
              damageVulnerability:6,
              fireExtinguishSuccess_percentage:65,
              fireExtinguishMaxTime_seconds:80,
              explosiveMass_kg : 27772,
              airspeed_damage:{
                damage_threshold_kt: 480, # Never exceed speed, http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II 
                warning_threshold_kt: 450,
                #1 kt over the threshold for 1 second will add 1% damage:
                damage_multiplier_percentpersecond: 0.5
              },
              gforce_damage: {
                  damage_enabled: 1,
                  warning_enabled: 1,
                  damage_threshold_g: {positive:9, negative:9},
                  warning_threshold_g: {positive:8, negative:8},
                  damage_multiplier_percentpersecond: {positive:3, negative:3 }  # higher = weaker aircraft
    
                  },          
              redout: {
                enabled: 1,
                parameters: {
                  blackout_onset_g: 7, #g-suit allows up to 9Gs, http://en.wikipedia.org/wiki/G-LOC 
                  blackout_complete_g: 10, #or even 10-12.  Maybe. http://forum.acewings.com/pop_printer_friendly.asp?ARCHIVE=true&TOPIC_ID=3588
                  redout_onset_g: -2,  #however, g-suit doesn't help with red-out.  Source: http://en.wikipedia.org/wiki/Greyout_(medical)
                  redout_complete_g: -3
                }        
              }  
             }
          }     
        
        } elsif ( string.match(aircraftname,"f6f*" ) ) {
        debprint ("Bombable: Loading F6F Hellcat main aircraft vulnerabilities"); 
        attsObject = {
          #########################################
          # DIMENSION DEFINITIONS
          #
          # All dimensions are in meters
          # source: http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II          
          #           
          dimensions : {                  
            width_m : 17.53,  #width of your object, ie, for aircraft, wingspan
            length_m : 16.26, #length of your object, ie, for aircraft, distance nose to tail
            height_m : 4.47, #height of your object, ie, for aircraft ground to highest point when sitting on runway
            
            damageRadius_m : 8, #typically 1/2 the longest dimension of the object. Hits within this distance of the 
                                #center of object have some possibility of damage
            vitalDamageRadius_m : 2, #typically the radius of the fuselage or cockpit or other most 
                                     # vital area at the center of the object.  Always smaller than damageRadius_m
                                    
            crashRadius_m : 6, #It's a crash if the main aircraft hits in this area.
                                
          },          
          vulnerabilities: {

            engineDamageVulnerability_percent : 7,
            fireVulnerability_percent:15,
            fireDamageRate_percentpersecond : .5,
            damageVulnerability:3.5,
            fireExtinguishSuccess_percentage:23,
            fireExtinguishMaxTime_seconds:30,
            explosiveMass_kg : 735,
            airspeed_damage:{
              damage_threshold_kt: 450, #VNE, http://forums.ubi.com/eve/forums/a/tpc/f/23110283/m/46710245
              warning_threshold_kt: 420,
              #1 kt over the threshold for 1 second will add 1% damage:
              damage_multiplier_percentpersecond: 0.5
            },
            gforce_damage: {
                                #data: http://www.amazon.com/Grumman-Hellcat-Pilots-Operating-Instructions/dp/1935327291/ref=sr_1_1?s=books&ie=UTF8&qid=1319249394&sr=1-1
                                #see particularly p. 59
                                #accel 'never exceed' limits are +7 and -3 Gs in all situations, and less in some situations
                damage_enabled: 1,  #boolean yes/no
                warning_enabled: 1, #boolean yes/no
                damage_threshold_g: {positive:15.6, negative:10}, # it's somewhat stronger built than the A6M2
                warning_threshold_g: {positive:12, negative:8},
                damage_multiplier_percentpersecond: {positive:12, negative:12 }
            },
            redout: {
              enabled: 1,
              parameters: {
                blackout_onset_g: 5, #no g-suit in WWI so really 6gs is pushing it
                blackout_complete_g: 7,
                redout_onset_g: -2.5,
                redout_complete_g: -3
              }        
            }  
          }   
        }
       
      } elsif ( string.match(aircraftname,"*sopwithCamel*" ) ) {
        debprint ("Bombable: Loading SopwithCamel main aircraft vulnerabilities");
        attsObject = {
        
          #########################################
          # DIMENSION DEFINITIONS
          #
          # All dimensions are in meters
          # source: http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II          
          #           
          dimensions : {                  
            width_m : 17.53,  #width of your object, ie, for aircraft, wingspan
            length_m : 16.26, #length of your object, ie, for aircraft, distance nose to tail
            height_m : 4.47, #height of your object, ie, for aircraft ground to highest point when sitting on runway
            
            damageRadius_m : 8, #typically 1/2 the longest dimension of the object. Hits within this distance of the 
                                #center of object have some possibility of damage
            vitalDamageRadius_m : 2, #typically the radius of the fuselage or cockpit or other most 
                                     # vital area at the center of the object.  Always smaller than damageRadius_m
                                    
            crashRadius_m : 6, #It's a crash if the main aircraft hits in this area.
                                
          },          
          vulnerabilities: {
            engineDamageVulnerability_percent : 7,
            fireVulnerability_percent:15,
            fireDamageRate_percentpersecond : .5,
            damageVulnerability:3.5,
            fireExtinguishSuccess_percentage:23,
            fireExtinguishMaxTime_seconds:30,
            explosiveMass_kg : 735,
            airspeed_damage:{
              damage_threshold_kt: 185, #max speed, level flight is 100 kt, so this is a guess
              warning_threshold_kt: 175,
              #1 kt over the threshold for 1 second will add 1% damage:
              damage_multiplier_percentpersecond: 0.5
            },
            gforce_damage: {
                damage_enabled: 1,
                warning_enabled: 1,
                damage_threshold_g: {positive:4, negative:3},
                warning_threshold_g: {positive:3, negative:2.5},
                damage_multiplier_percentpersecond: {positive:12, negative:12 }
  
                },          
            redout: {
              enabled: 1,
              parameters: {
                blackout_onset_g: 3,
                blackout_complete_g: 4,
                redout_onset_g: -2,
                redout_complete_g: -3
              }        
            }  
          }   
        }  
      } elsif ( string.match(aircraftname, "*spadvii*" )  ) {
      
        debprint ("Bombable: Loading SPAD VII main aircraft vulnerabilities");
        attsObject = {
          #########################################
          # DIMENSION DEFINITIONS
          #
          # All dimensions are in meters
          # source: http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II          
          #           
          dimensions : {                  
            width_m : 17.53,  #width of your object, ie, for aircraft, wingspan
            length_m : 16.26, #length of your object, ie, for aircraft, distance nose to tail
            height_m : 4.47, #height of your object, ie, for aircraft ground to highest point when sitting on runway
            
            damageRadius_m : 8, #typically 1/2 the longest dimension of the object. Hits within this distance of the 
                                #center of object have some possibility of damage
            vitalDamageRadius_m : 2, #typically the radius of the fuselage or cockpit or other most 
                                     # vital area at the center of the object.  Always smaller than damageRadius_m
                                    
            crashRadius_m : 6, #It's a crash if the main aircraft hits in this area.
                                
          },
          
          vulnerabilities: {
            engineDamageVulnerability_percent : 3,
            fireVulnerability_percent:20,
            fireDamageRate_percentpersecond : .2,
            damageVulnerability:4,
            fireExtinguishSuccess_percentage:10,
            fireExtinguishMaxTime_seconds:100,
            explosiveMass_kg : 735,
            airspeed_damage:{
              damage_threshold_kt: 195, #max speed, level flight is 103 kt, so this is a guess based on that plus Spad's rep as able to hold together in "swift dives" better than most
              warning_threshold_kt: 185,
              #1 kt over the threshold for 1 second will add 1% damage:
              damage_multiplier_percentpersecond: 0.4
            },
            gforce_damage: {
                damage_enabled: 1,
                warning_enabled: 1,
                #"swift dive" capability must mean it is a bit more structurally 
                #   sound than camel/DR1
                damage_threshold_g: {positive:4.5, negative:3},
                warning_threshold_g: {positive:3, negative:2.5},
                damage_multiplier_percentpersecond: {positive:9, negative:9 }
  
                },          
            redout: {
              enabled: 1,
              parameters: {
                blackout_onset_g: 3,
                blackout_complete_g: 4,
                redout_onset_g: -2,
                redout_complete_g:-3
              }        
            }  
          }
        }     
      } elsif ( string.match(aircraftname,"*fkdr*" ) ) {
        debprint ("Bombable: Loading Fokker DR.1 main aircraft vulnerabilities");
        attsObject = {
          #########################################
          # DIMENSION DEFINITIONS
          #
          # All dimensions are in meters
          # source: http://en.wikipedia.org/wiki/Fairchild_Republic_A-10_Thunderbolt_II          
          #           
          dimensions : {                  
            width_m : 17.53,  #width of your object, ie, for aircraft, wingspan
            length_m : 16.26, #length of your object, ie, for aircraft, distance nose to tail
            height_m : 4.47, #height of your object, ie, for aircraft ground to highest point when sitting on runway
            
            damageRadius_m : 8, #typically 1/2 the longest dimension of the object. Hits within this distance of the 
                                #center of object have some possibility of damage
            vitalDamageRadius_m : 2, #typically the radius of the fuselage or cockpit or other most 
                                     # vital area at the center of the object.  Always smaller than damageRadius_m
                                    
            crashRadius_m : 6, #It's a crash if the main aircraft hits in this area.
                                
          },
          
          vulnerabilities: {
                  
            engineDamageVulnerability_percent : 3,
            fireVulnerability_percent:20,
            fireDamageRate_percentpersecond : .2,
            damageVulnerability:4,
            fireExtinguishSuccess_percentage:10,
            fireExtinguishMaxTime_seconds:100,
            explosiveMass_kg : 735,
            airspeed_damage:{
              damage_threshold_kt: 170, #max speed, level flight is 100 kt, so this is a guess based on that plus the DR1's reputation for wing damage at high speeds
              warning_threshold_kt: 155,
              #1 kt over the threshold for 1 second will add 1% damage:
              damage_multiplier_percentpersecond: 0.8
            },
  
            gforce_damage: {
                damage_enabled: 1,
                warning_enabled: 1,
                #wing breakage problems indicate weaker construction 
                #    than SPAD VII, Sopwith Camel              
                damage_threshold_g: {positive:3.8, negative:2.8},
                warning_threshold_g: {positive:3, negative:2.2},
                damage_multiplier_percentpersecond: {positive:14, negative:14 }
            },          
            redout: {
              enabled: 1,
              parameters: {
                blackout_onset_g: 4,
                blackout_complete_g: 5,
                redout_onset_g: -2,
                redout_complete_g:-3
              }        
            }  
          }
       }  
        
    }   
      

  props.globals.getNode(""~attributes_pp, 1).setValues(attsObject);
  attributes[""]= attsObject;
  #put the redout properties in place, too; wait a couple of 
  # seconds so we aren't overwritten by the redout.nas subroutine:
  settimer ( func { 
  
     props.globals.getNode("/sim/rendering/redout/enabled", 1).setValue(attsObject.vulnerabilities.redout.enabled);
     props.globals.getNode("/sim/rendering/redout/parameters/blackout-onset-g", 1).setValue(attsObject.vulnerabilities.redout.parameters.blackout_onset_g);
     props.globals.getNode("/sim/rendering/redout/parameters/blackout-complete-g", 1).setValue(attsObject.vulnerabilities.redout.parameters.blackout_complete_g);
     props.globals.getNode("/sim/rendering/redout/parameters/redout-onset-g", 1).setValue(attsObject.vulnerabilities.redout.parameters.redout_onset_g);
     props.globals.getNode("/sim/rendering/redout/parameters/redout-complete-g", 1).setValue(attsObject.vulnerabilities.redout.parameters.redout_complete_g);
     
     }, 3);


  #reset the vulnerabilities for the main object whenever FG
  # reinits.  
  # Important especially for setting redout/blackout, which otherwise
  # reverts to FG's defaults on reset.  
  # We need to do it here so that if some outside aircraft
  # calls setVulnerabilities with its own attsObject
  # we will be able to use that here & reinit with that attsObject
  #           
  attsSet=getprop (""~attributes_pp~"/attributes-set");
  if (attsSet==nil) attsSet=0; 
  if (attsSet==0) { setlistener("/sim/signals/reinit", func {
    setAttributes(attsObject)} );
    
    #also set the default gforce/speed damage/warning enabled/disabled
    # but only on initial startup, not on reset    
    
    if (getprop (GF_damage_menu_pp ~"/damage_enabled")==nil)     
      props.globals.getNode(GF_damage_menu_pp ~"/damage_enabled", 1).setValue(attsObject.vulnerabilities.gforce_damage.damage_enabled);
    if (getprop (GF_damage_menu_pp ~"/warning_enabled")==nil)
      props.globals.getNode(GF_damage_menu_pp ~"/warning_enabled", 1).setValue(attsObject.vulnerabilities.gforce_damage.warning_enabled);
  
  
    
    
  }
  
  
  props.globals.getNode(""~attributes_pp~"/attributes-set", 1).setValue(1);
  
}
  
  
####################################################
#start a fire in a given location & associated with a given object
#
#
#A fire is different than the smoke, contrails, and flares below because
#when the fire is burning it adds damage to the object and eventually
#destroys it.
#
#object is given by "myNodeName" and directory path to the model in "model"
#Also sets the fire trigger on the object itself so it knows it is on fire
#and saves the name of the fire (model) node so the object can find
#the fire (model) it is associated with to update it etc.
#Returns name of the node with the newly started fire object (model)
var startFire = func (myNodeName="", model="")
  {
  #if (myNodeName=="") myNodeName="/environment";
  #if there is already a fire going/associated with this object
  # then we don't want to start another  
  var currFire= getprop(""~myNodeName~"/bombable/fire-particles/fire-particles-model");
  if ((currFire != nil) and (currFire != "")) {
    setprop(""~myNodeName~"/bombable/fire-particles/fire-burning", 1); 
    return currFire;
  }  
  
      
  if (model==nil or model=="") model="AI/Aircraft/Fire-Particles/fire-particles.xml";
  var fireNode=put_tied_model(myNodeName, model);
  
  # if (myNodeName!="") type=props.globals.getNode(myNodeName).getName();
  #else type="";
  #if (type=="multiplayer") mp_send_damage(myNodeName, 0);
  
  
  
  #var fire_node=geo.put_model("Models/Effects/Wildfire/wildfire.xml", lat, lon, alt*feet2meters);
  #print ("started fire! ", myNodeName);
  
  #turn off the fire after user-set amount of time (default 1800 seconds)
  var burnTime=getprop ("/bombable/fire-particles/fire-burn-time");
  if (burnTime==0 or burnTime==nil) burnTime=1800;
  settimer (func {deleteFire(myNodeName,fireNode)}, burnTime);

  #name of this prop is "/models" + getname() + [ getindex() ]
  fireNodeName="/models/" ~ fireNode.getName() ~ "[" ~ fireNode.getIndex() ~ "]";
     

   setprop(""~myNodeName~"/bombable/fire-particles/fire-burning", 1);
   setprop(""~myNodeName~"/bombable/fire-particles/fire-particles-model", fireNodeName);
   
   return fireNodeName; #we usually start with the name & then use props.globals.getNode(nodeName) to get the node object if necessary.  
   #you can also use cmdarg().getPath() to get the full path from the node
   
}




####################################################
#Delete any of the various smoke, contrail, flare, etc. objects
#and unlink the fire from the smoke object.
#

var deleteSmoke = func (smokeType, myNodeName="",fireNode="") {
    
    #if (myNodeName=="") myNodeName="/environment";
    
    if (fireNode=="") {

        fireNodeName=getprop(""~myNodeName~"/bombable/fire-particles/"~smokeType~"-particles-model");
        if (fireNodeName==nil) return;
        fireNode = props.globals.getNode(fireNodeName);
    }
    #remove the fire node/model altogether
    if (fireNode != nil) fireNode.remove();
    
    #turn off the object's fire trigger & unlink it from its fire model
    setprop(""~myNodeName~"/bombable/fire-particles/"~smokeType~"-burning", 0);
    setprop(""~myNodeName~"/bombable/fire-particles/"~smokeType~"-particles-model", "");

   #if (myNodeName!="") type=props.globals.getNode(myNodeName).getName();
   #else type="";
   #if (type=="multiplayer") mp_send_damage(myNodeName, 0);
   
  
  

}


####################################################
# Smoke is like a fire, but doesn't cause damage & can use one of 
# several different models to create different effects.
#
# smokeTypes are flare, smoketrail, pistonexhaust, contrail, damagedengine
#
# This func starts a flare in a given location & associated with a given object
#object is given by "myNodeName" and directory path to the model in "model"
#Also sets the fire burning flag on the object itself so it knows it is on fire
#and saves the name of the fire (model) node so the object can find
#the fire (model) it is associated with to update it etc.
#Returns name of the node with the newly started fire object (model)
var startSmoke = func (smokeType, myNodeName="", model="")
  {
  if (myNodeName=="") myNodeName=""; 
  #if there is already smoke of this type going/associated with this object
  # then we don't want to start another  
  var currFire= getprop(""~myNodeName~"/bombable/fire-particles/"~smokeType~"-particles-model");
  if ((currFire != nil) and (currFire != "")) return currFire;
  
      
  if (model==nil or model=="") model="AI/Aircraft/Fire-Particles/"~smokeType~"-particles.xml";
  var fireNode=put_tied_model(myNodeName, model);
  
  
  #var fire_node=geo.put_model("Models/bombable/Wildfire/wildfire.xml", lat, lon, alt*feet2meters);                                             
  #debprint ("started fire! "~ myNodeName);
  
  #turn off the flare after user-set amount of time (default 1800 seconds)
  var burnTime=getprop (burntime1_pp~smokeType~burntime2_pp);
  if (burnTime==0 or burnTime==nil) burnTime=1800;
  #burnTime=-1 means leave it on indefinitely
  if (burnTime >= 0) settimer (func {deleteSmoke(smokeType, myNodeName,fireNode)}, burnTime);

  #name of this prop is "/models" + getname() + [ getindex() ]
  fireNodeName="/models/" ~ fireNode.getName() ~ "[" ~ fireNode.getIndex() ~ "]";
  
   # if (myNodeName!="") type=props.globals.getNode(myNodeName).getName();
   #else type="";
   #if (type=="multiplayer") mp_send_damage(myNodeName, 0);
   
  

   setprop(""~myNodeName~"/bombable/fire-particles/"~smokeType~"-burning", 1);
   setprop(""~myNodeName~"/bombable/fire-particles/"~smokeType~"-particles-model", fireNodeName);
   
   return fireNodeName; #we usually pass around the name & then use props.globals.getNode(nodeName) to get the node object if necessary.  
}


####################################################
#reset damage & fires for main object
# 
# 
var reset_damage_fires = func  {
  
    deleteFire("");
    deleteSmoke("damagedengine", "");
  	setprop("/bombable/attributes/damage", 0);
  	setprop ("/bombable/on-ground",  0 );
  	#blow away the locks for MP communication--shouldn't really
    # be needed--but just a little belt & suspendors things here
    # to make sure that no old damage (prior to the reset) is sent
    # to other aircraft again after the reset, and that none of the 
    # locks are stuck.                            
    props.globals.getNode("/bombable").removeChild("locks",0);
  	
  	var msg_add="";
    var msg=reset_msg();
  	if (msg != "" and getprop(MP_share_pp) and getprop (MP_broadcast_exists_pp) ) {
      debprint ("Bombable RESET: MP sending: "~msg);
      mpsend(msg);
      msg_add=" and broadcast via multi-player";
    } 
      
      
    debprint ("Bombable: Damage level & smoke reset for main object"~msg_add);

    var msg= "Your damage reset to 0%";  
    selfStatusPopupTip (msg, 30);
  
}

####################################################
# resetAllAIDamage
# reset the damage, smoke & fires from all AI object with bombable operative
# TODO if an aircraft is crashing, it stays crashing despite this.
#

var revitalizeAllAIObjects = func (revitType="aircraft") {

     ai = props.globals.getNode ("/ai/models").getChildren();
     
     #var m_per_deg_lat=getprop ("/bombable/sharedconstants/m_per_deg_lat");
     #var m_per_deg_lon=getprop ("/bombable/sharedconstants/m_per_deg_lon");
     var latPlusMinus=1; if (rand()>.5) latPlusMinus=-1;
     var lonPlusMinus=1; if (rand()>.5) lonPlusMinus=-1;
     var heading_deg = rand() * 360; #it's helpful to have them all going in the same
     #direction, in case AI piloting is turned off (they stay together rather than dispersing)
     var waitTime_sec=0;
     
     foreach (elem;ai) {
     
        #only do this for the type named in the function call
        type=elem.getName();
        if (type != revitType) continue;
        
        aiName=type ~ "[" ~ elem.getIndex() ~ "]";
        
        #only if bombable initialized
        #experimental: doing this for ALL aircraft/objects regardless of bombable status.
        #if (props.globals.getNode ( "/ai/models/"~aiName~"/bombable" ) == nil) continue;
        
        
        #reset damage, smoke, fires for all objects that have bombable initialized
        #even does it for multiplayer objects, which is not completely proper (the MP bombable
        #keeps their 'real' damage total remotely), but might help in case of MP malfunction of some sort, and doesn't hurt in the meanwhile
        resetBombableDamageFuelWeapons ("/ai/models/" ~ aiName);
          
        setprop ("ai/models/"~aiName~"/controls/flight/target-pitch", 0);
        setprop ("ai/models/"~aiName~"/controls/flight/target-roll", 0);
        setprop ("ai/models/"~aiName~"/orientation/roll-deg", 0); 

        #settimer & increased waittime helps avoid segfault that seems to happen
        #to FG too often when many models appear all at once
        #settimer ( func {        
          newlat_deg = getprop ("/position/latitude-deg") + latPlusMinus * (3000+rand()*500)/m_per_deg_lat ;
          newlon_deg = getprop ("/position/longitude-deg") + lonPlusMinus * (4000+rand()*500)/m_per_deg_lon;
          setprop ("ai/models/"~aiName~"/position/latitude-deg",  newlat_deg );
          setprop ("ai/models/"~aiName~"/position/longitude-deg",  newlon_deg );
          elev_ft = elev (newlat_deg,newlon_deg);
        
          if (type=="aircraft") {
            alt_ft=getprop ("/position/altitude-ft")+100;  
            if (alt_ft-500<elev_ft) alt_ft=elev_ft+500;
          } else {
            alt_ft= elev_ft;
          }
          
          setprop ("ai/models/"~aiName~"/position/altitude-ft", alt_ft);
          setprop ("ai/models/"~aiName~"/controls/flight/target-alt", alt_ft);
          setprop ("ai/models/"~aiName~"/controls/flight/target-hdg", heading_deg);
          setprop ("ai/models/"~aiName~"/orientation/true-heading-deg", heading_deg);
  
          #setting these stops the relocate function from relocating them back
          setprop("ai/models/"~aiName~"/position/previous/latitude-deg", newlat_deg);
          setprop("ai/models/"~aiName~"/position/previous/longitude-deg", newlon_deg);
          setprop("ai/models/"~aiName~"/position/previous/altitude-ft", alt_ft);
          
          var cart = geodtocart(newlat_deg, newlon_deg, alt_ft*feet2meters); # lat/lon/alt(m)
          
        
          setprop("ai/models/"~aiName~"/position/previous/global-x", cart[0]);
          setprop("ai/models/"~aiName~"/position/previous/global-y", cart[1]);
          setprop("ai/models/"~aiName~"/position/previous/global-z", cart[2]);
        #}, waitTime_sec );
        #waitTime_sec+=4;
         
        var min_vel_kt=getprop( "ai/models/"~aiName~"/bombable/attributes/velocities/minSpeed_kt");
        var cruise_vel_kt=getprop( "ai/models/"~aiName~"/bombable/attributes/velocities/cruiseSpeed_kt");
        var attack_vel_kt=getprop( "ai/models/"~aiName~"/bombable/attributes/velocities/attackSpeed_kt");
        var max_vel_kt=getprop( "ai/models/"~aiName~"/bombable/attributes/velocities/maxSpeed_kt");
        
        #defaults
        if (type=="aircraft") {
          if (min_vel_kt==nil or min_vel_kt<1) min_vel_kt=50;
          if (cruise_vel_kt==nil or cruise_vel_kt<1) {
               cruise_vel_kt=2*min_vel_kt;
               #they're at 82% to 102% of your current airspeed
               var vel=getprop ("/velocities/airspeed-kt") * (.82 + rand()*.2);
          } else { var vel=0; }    
          if (attack_vel_kt==nil or attack_vel_kt<=cruise_vel_kt) attack_vel_kt=1.5*cruise_vel_kt;
          
          if (max_vel_kt==nil or max_vel_kt<=attack_vel_kt) max_vel_kt=1.5*attack_vel_kt;
        } else {
          if (min_vel_kt==nil or min_vel_kt<1) min_vel_kt=10;
          if (cruise_vel_kt==nil or cruise_vel_kt<1) {
             cruise_vel_kt=2*min_vel_kt;
             var vel=15;             
          } else { var vel=0;}
            
          if (attack_vel_kt==nil or attack_vel_kt<=cruise_vel_kt) attack_vel_kt=1.5*cruise_vel_kt;
          if (max_vel_kt==nil or max_vel_kt<=attack_vel_kt) max_vel_kt=1.5*attack_vel_kt;
        }
        debprint ("vel1:", vel);
        
        if (vel<min_vel_kt or vel==0) vel=(attack_vel_kt-cruise_vel_kt)*rand() + cruise_vel_kt;
        if (vel>max_vel_kt) vel=max_vel_kt;
        
        debprint ("vel2:", vel); 
        setprop ("ai/models/"~aiName~"/velocities/true-airspeed-kt", vel);
        setprop ("ai/models/"~aiName~"/controls/flight/target-spd", vel);     
     
     }
     
     if (revitType=="aircraft") {
        var msg = "All AI Aircraft have damage reset and are at your altitude about 5000 meters off";
     } else {
        var msg = "All AI ground/water craft have damage reset and are about 5000 meters off";
     }   
     
     #many times when the objects are relocated they initialize and
     # in doing so call reinit GUI.  This can cause a segfault if 
     # we are in the middle of popping up our message.  So best to wait a while
     # before doing it . . .                
     settimer ( func { targetStatusPopupTip (msg, 2);}, 13);
     debprint ("Bombable: " ~ msg);

}

####################################################
# resetBombableDamageFuelWeapons
# reset the damage, smoke & fires from an AI aircraft, or the main aircraft
#  myNodeName = the AI node to reset, or set myNodeName="" for the main 
# #aircraft.

var resetBombableDamageFuelWeapons = func (myNodeName) {
         
         
         
         #if (myNodeName=="" or myNodeName=="environment") myNodeName="/environment";
         debprint ("Bombable: Resetting damage level and fires for ", myNodeName);
         
         #don't do this for objects that don't even have bombable initialized
         if (props.globals.getNode ( ""~myNodeName~"/bombable" ) == nil) return;
         
         if (myNodeName=="") {
            #main aircraft   
            reset_damage_fires();
           
         } else {         
           #ai objects
            
           #refill fuel & weapons                      
           stores.fillFuel(myNodeName, 1);
           stores.fillWeapons (myNodeName, 1);
           deleteFire(myNodeName);
           deleteSmoke("damagedengine", myNodeName);
           if (props.globals.getNode ( ""~myNodeName~"/bombable/attributes/damage" ) != nil) {  
           
                 
              setprop(""~myNodeName~"/bombable/attributes/damage", 0);
              setprop(""~myNodeName~"/bombable/exploded", 0);
              setprop(""~myNodeName~"/bombable/on-ground", 0);
              
           	  setprop(""~myNodeName~"/bombable/attributes/damageAltAddCurrent_ft", 0);
              setprop(""~myNodeName~"/bombable/attributes/damageAltAddCumulative_ft",0);
                
              #take the opportunity to reset the pilot's abilities, giving them  
              # a new personality when they come back alive       
              pilotAbility = math.pow (rand(), 1.5) ;
              if (rand()>.5) pilotAbility=-pilotAbility;
              setprop(""~myNodeName~"/bombable/attack-pilot-ability", pilotAbility);
              # Set an individual pilot weapons ability, -1 to 1, with 0 being average
              pilotAbility = math.pow (rand(), 1.5) ;
              if (rand()>.5) pilotAbility=-pilotAbility;
              setprop(""~myNodeName~"/bombable/weapons-pilot-ability", pilotAbility);

              
              if (myNodeName != "") {
                msg = "Damage reset to 0 for " ~ myNodeName;
                targetStatusPopupTip (msg, 2);
              }  
           }
         }    

}




####################################################
# resetAllAIDamage
# reset the damage, smoke & fires from all AI object with bombable operative

var resetAllAIDamage = func {

     ai = props.globals.getNode ("/ai/models").getChildren();
     foreach (elem;ai) {
        aiName=elem.getName() ~ "[" ~ elem.getIndex() ~ "]";
        
        #reset damage, smoke, fires for all objects that have bombable initialized
        #even does it for multiplayer objects, which is not completely proper (the MP bombable
        #keeps their 'real' damage total remotely), but might help in case of MP malfunction of some sort, and doesn't hurt in the meanwhile
        if (props.globals.getNode ( "/ai/models/"~aiName~"/bombable" ) != nil) {
          resetBombableDamageFuelWeapons ("/ai/models/" ~ aiName);
        }  
     
     }
     
     msg = "Damage reset to 0 for all AI objects";
     targetStatusPopupTip (msg, 2);
     debprint ("Bombable: "~msg);
     

}

####################################################
# resetMainAircraftDamage
# reset the damage, smoke & fires from the main aircraft/object

var resetMainAircraftDamage = func {

     resetBombableDamageFuelWeapons ("");
     
     msg = "Damage reset to 0 for main aircraft - you'll need to turn on your magnetos/restart your engines";
     selfStatusPopupTip (msg, 2);
     debprint ("Bombable: "~msg);     

}


############################################################

####################################################
#Add a new menu item to turn smoke on/off
#todo: need to integrate this into the menus rather than just 
#arbitrarily adding it to menu[97]
#
#This function adds the dialog object to an actual GUI menubar item


var init_bombable_dialog = func () {
       #return; #gui prob
       
       #we set bomb_menuNum to -1 at initialization time.  
       #On reinit & some other times, this routine will be called again
       #so if bomb_menuNum != -1 we know not to seek out another new menu number
       #Without this check, we'd get a new Bombable menu added each time FG reinits
       #or re-positions. 
       if (bomb_menuNum==nil or bomb_menuNum==-1) {
        #find the next open menu number/kludge
         bomb_menuNum=97; #the default
         for (var i=0;i<300;i+=1) {
           p=props.globals.getNode("/sim/menubar/default/menu["~i~"]");
           if ( typeof(p) == "nil" ) {
              bomb_menuNum=i;
              break;
           }   
         }
        } 
        
        #init the main bombable options menu
        #todo: figure out how to position it in the center of the screen or somewhere better
        dialog.init(0,0);
        
        #make the GUI menubar item to select the options menu
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/enabled", 1).setBoolValue(1);
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/label", 1).setValue("Bombable");
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/item/enabled", 1).setBoolValue(1);
        #Note: the label must be distinct from all other labels in the menubar
        #or you will get duplicate functionality with the other menu item
        #sharing the same label
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/item/label", 1).setValue("Bombable Options"); #must be unique name from all others in the menubar or they both pop up together
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/item/binding/command", 1).setValue("nasal");
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/item/binding/script", 1).setValue("bombable.dialog.create()");

        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/item[1]/label", 1).setValue("Bombable Statistics"); #must be unique name from all others in the menubar or they both pop up together
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/item[1]/binding/command", 1).setValue("nasal");
        props.globals.getNode ("/sim/menubar/default/menu["~bomb_menuNum~"]/item[1]/binding/script", 1).setValue("bombable.records.display_results()");
        
        
        
       #reinit makes the property changes to both the GUI & input become active
       #the delay is to avoid a segfault under dev version of FlightGear, 2010/09/07
       #This just a workaround, a real fix would like:  
       #  overwriting preferences.xml with a new one including a line like <menubar include="Dialogs/bombable.xml"/>'
       #Thx goes to user Citronnier for tracking this down  
       #settimer (func {fgcommand("reinit")}, 15);
       #As of FG 2.4.0, a straight "reinit" leads to FG crash or the dreaded NAN issue
       #at least with some aircraft.  Reinit/gui (as below) gets around this problem.
       #fgcommand("reinit", props.Node.new({subsystem : "gui"}));
       
       #OK . . . per gui.nas line 63, this appears to be the right way to do this:
       fgcommand ("gui-redraw");
}
	
var targetStatusPopupTip = func (label, delay = 5, override = nil) {	
    
    var tmpl = props.Node.new({
            name : "PopTipTarget", modal : 0, layout : "hbox",
            y: 70,
            text : { label : label, padding : 6 }
    });
    if (override != nil) tmpl.setValues(override);
   
    popdown(tipArgTarget);
    fgcommand("dialog-new", tmpl);
    fgcommand("dialog-show", tipArgTarget);

    currTimerTarget += 1;
    var thisTimerTarget = currTimerTarget;

    # Final argument is a flag to use "real" time, not simulated time
    settimer(func { if(currTimerTarget == thisTimerTarget) { popdown(tipArgTarget) } }, delay, 1);
}

var selfStatusPopupTip = func (label, delay = 10, override = nil) {	
    #return; #gui prob
    var tmpl = props.Node.new({
            name : "PopTipSelf", modal : 0, layout : "hbox",
            y: 140,
            text : { label : label, padding : 6 }
    });
    if (override != nil) tmpl.setValues(override);
   
    popdown(tipArgSelf);
    fgcommand("dialog-new", tmpl);
    fgcommand("dialog-show", tipArgSelf);

    currTimerSelf += 1;
    var thisTimerSelf = currTimerSelf;

    # Final argument is a flag to use "real" time, not simulated time
    settimer(func { if(currTimerSelf == thisTimerSelf) { popdown(tipArgSelf) } }, delay, 1);
}

var popdown = func ( tipArg ) { 
  #return; #gui prob
  fgcommand("dialog-close", tipArg); 
}
    


###############################################################################
## Set up Bombable Menu to turn on/off contrails etc.
## Based on the WildFire configuration dialog,
## which is partly based on Till Bush's multiplayer dialog
## to start, do dialog.init(30,30); dialog.create();

var CONFIG_DLG = 0;

var dialog = {
#################################################################
    init : func (x = nil, y = nil) {
        me.x = x;
        me.y = y;
        me.bg = [0, 0, 0, 0.3];    # background color
        me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
        #
        # "private"
        me.title = "Bombable";
        me.basenode = props.globals.getNode("/bombable/fire-particles");
        me.dialog = nil;
        me.namenode = props.Node.new({"dialog-name" : me.title });
        me.listeners = [];
    },
#################################################################
    create : func {
        if (me.dialog != nil)
            me.close();
        #return; #gui prob
        me.dialog = gui.Widget.new();
        me.dialog.set("name", me.title);
        if (me.x != nil)
            me.dialog.set("x", me.x);
        if (me.y != nil)
            me.dialog.set("y", me.y);

        me.dialog.set("layout", "vbox");
        me.dialog.set("default-padding", 0);
        var titlebar = me.dialog.addChild("group");
        titlebar.set("layout", "hbox");
        titlebar.addChild("empty").set("stretch", 1);
        titlebar.addChild("text").set("label", "Bombable Objects Settings");
        var w = titlebar.addChild("button");
        w.set("pref-width", 16);
        w.set("pref-height", 16);
        w.set("legend", "");
        w.set("default", 0);
        w.set("key", "esc");
        w.setBinding("nasal", "bombable.dialog.destroy(); ");
        w.setBinding("dialog-close");
        me.dialog.addChild("hrule");

        var buttonBar1 = me.dialog.addChild("group");
        buttonBar1.set("layout", "hbox");
        buttonBar1.set("default-padding", 10);
     
        lresetSelf = buttonBar1.addChild("button");
        lresetSelf.set("legend", "Reset Main Aircraft Damage");
        lresetSelf.set("equal", 1);                
        lresetSelf.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lresetSelf.prop().getNode("binding[0]/script", 1).setValue("bombable.resetMainAircraftDamage();");

        lresetAI = buttonBar1.addChild("button");
        lresetAI.set("legend", "Reset AI Objects Damage");
        lresetAI.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lresetAI.prop().getNode("binding[0]/script", 1).setValue("bombable.resetAllAIDamage();");

        #respawning often makes AI objects init or reinit, which sometimes
        # includes GUI reinit.  So we need to save/close the dialogue first 
        # thing; otherwise segfault is likely        
        lrevitAIAir = buttonBar1.addChild("button");
        lrevitAIAir.set("legend", "Respawn AI Aircraft");
        
        lrevitAIAir.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lrevitAIAir.prop().getNode("binding[0]/script", 1).setValue("bombable.revitalizeAllAIObjects(\"aircraft\");");
        lrevitAIAir.prop().getNode("binding[1]/command", 1).setValue("nasal");
        lrevitAIAir.prop().getNode("binding[1]/script", 1).setValue("bombable.bombable_dialog_save();");
        lrevitAIAir.prop().getNode("binding[2]/command", 1).setValue("dialog-apply");
        lrevitAIAir.prop().getNode("binding[3]/command", 1).setValue("dialog-close");        

        lrevitAIObj = buttonBar1.addChild("button");
        lrevitAIObj.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lrevitAIObj.prop().getNode("binding[0]/script", 1).setValue("bombable.revitalizeAllAIObjects(\"ship\");");
        lrevitAIObj.prop().getNode("binding[1]/command", 1).setValue("nasal");
        lrevitAIObj.prop().getNode("binding[1]/script", 1).setValue("bombable.bombable_dialog_save();");


        lrevitAIObj.set("legend", "Respawn AI Ground/Water Craft");
        lrevitAIObj.prop().getNode("binding[2]/command", 1).setValue("dialog-apply");
        lrevitAIObj.prop().getNode("binding[3]/command", 1).setValue("dialog-close");


#        lresetAI = buttonBar1.addChild("button");
#        lresetAI.set("legend", "Reset All Damage (Main & AI)");
#        lresetAI.prop().getNode("binding[0]/command", 1).setValue("nasal");
#        lresetAI.prop().getNode("binding[0]/script", 1).setValue("bombable.resetAllAIDamage();bombable.resetMainAircraftDamage();");

        me.dialog.addChild("hrule");


        var content = me.dialog.addChild("group");
        content.set("layout", "vbox");
        content.set("halign", "center");
        content.set("default-padding", 5);
        
        
        #triggers (-trigger) are the overall on/off flag for that type of fire/smoke globally in Bombable
        # burning (-burning) is the local flag telling whether the type of 
        # fire/smoke is burning on that particle node/aircraft
        #                                                                        
        foreach (var b; [["Bombable module enabled", bomb_menu_pp~"bombable-enabled", "checkbox"],
                         ["", "", "hrule"],
                         ["Weapon realism (your weapons)", bomb_menu_pp~"main-weapon-realism-combo", "combo", 300, ["Ultra-realistic", "Normal", "Easier", "Dead easy"]],
                         #["AI aircraft can shoot at you", bomb_menu_pp~"ai-aircraft-weapons-enabled", "checkbox"],
                         ["AI Weapon effectiveness (AI aircraft's weapons)", bomb_menu_pp~"ai-weapon-power-combo", "combo", 300, ["Much more effective", "More effective", "Normal", "Less effective", "Much less effective", "Disabled (they can't shoot at you)"]],

                         #["AI fighter aircraft maneuver and attack", bomb_menu_pp~"ai-aircraft-attack-enabled", "checkbox"],
                         ["AI aircraft flying/dogfighting skill", bomb_menu_pp~"ai-aircraft-skill-combo", "combo", 300, ["Very skilled", "Above average", "Normal", "Below average", "Unskilled", "Disabled (AI aircraft can't maneuver)"]],        
                         ["Bombable-via-multiplayer enabled", MP_share_pp, "checkbox"],
                         ["Excessive acceleration/speed warnings", GF_damage_menu_pp~"warning_enabled", "checkbox"],   
                         ["Excessive acceleration/speed damages aircraft", GF_damage_menu_pp~"damage_enabled", "checkbox"],
                         ["Weapon impact flack enabled", trigger1_pp~"flack"~trigger2_pp, "checkbox"],        
                         ["AI weapon fire visual effect", trigger1_pp~"ai-weapon-fire-visual"~trigger2_pp, "checkbox"],
                         ["Fires/Explosions enabled", trigger1_pp~"fire"~trigger2_pp, "checkbox"],
                         ["Jet Contrails enabled", trigger1_pp~"jetcontrail"~trigger2_pp, "checkbox"],
                         ["Smoke Trails enabled", trigger1_pp~"smoketrail"~trigger2_pp, "checkbox"],
                         ["Piston engine exhaust enabled", trigger1_pp~"pistonexhaust"~trigger2_pp, "checkbox"],
                         ["Damaged engine smoke enabled", trigger1_pp~"damagedengine"~trigger2_pp, "checkbox"],
                         ["Flares enabled", trigger1_pp~"flare"~trigger2_pp, "checkbox"],              
                         #["Easy mode enabled (twice as easy to hit targets; AI aircraft do easier manuevers; may combine w/Super Easy)", bomb_menu_pp~"easy-mode", "checkbox"],
                         #["Super Easy Mode (3X as easy to hit targets; damaged tripled; AI aircraft do yet easier manuevers)", bomb_menu_pp~"super-easy-mode", "checkbox"],
                         ["AI ground detection: Can be disabled to improve framerate when your AI scenarios are far above the ground", bomb_menu_pp~"ai-ground-loop-enabled", "checkbox"],        

                         
                         #["AI Weapon Effectiveness", bomb_menu_pp~"ai-weapon-power", "slider", 200, 0, 100 ],
                         
                         ["Print debug messages to console", bomb_menu_pp~"debug", "checkbox"]
                         ]
                         ) {
            var w = content.addChild(b[2]);
            w.node.setValues({"label"    : b[0],
                              "halign"   : "left",
                              "property" : b[1],
                              # "width"    : "200",
                              
                              });
                              
            if (b[2]=="select" or b[2]=="combo" or b[2]=="list" ){
               
              w.node.setValues({"pref-width"    : b[3],
                              });
              foreach (var r; b[4]) {
               var newentry = w.addChild("value");
               newentry.node.setValue(r);
              }
            }  
            
            if (b[2]=="slider"){
               
              w.node.setValues({"pref-width"    : b[3],
                                 "min" : b[4],
                                 "max" : b[5],
                              });
              
              
            }
            

        }
        me.dialog.addChild("hrule");
        
        var buttonBar = me.dialog.addChild("group");
        buttonBar.set("layout", "hbox");
        buttonBar.set("default-padding", 10);
     
        lsave = buttonBar.addChild("button");
        lsave.set("legend", "Save");
        lsave.set("default", 1);
        lsave.set("equal", 1);
        lsave.prop().getNode("binding[0]/command", 1).setValue("dialog-apply");                
        lsave.prop().getNode("binding[1]/command", 1).setValue("nasal");
        lsave.prop().getNode("binding[1]/script", 1).setValue("bombable.bombable_dialog_save();");
        lsave.prop().getNode("binding[2]/command", 1).setValue("dialog-close");

        lcancel = buttonBar.addChild("button");
        lcancel.set("legend", "Cancel");
        lcancel.set("equal", 1);
        lcancel.prop().getNode("binding[0]/command", 1).setValue("dialog-close");

        # Load button.
        #var load = me.dialog.addChild("button");
        #load.node.setValues({"legend"    : "Load Wildfire log",
        #                      "halign"   : "center"});
        #load.setBinding("nasal",
        #                "wildfire.dialog.select_and_load()");

        fgcommand("dialog-new", me.dialog.prop());
        fgcommand("dialog-show", me.namenode);
    },
#################################################################
    close : func {
        #return; #gui prob
        fgcommand("dialog-close", me.namenode);
    },
#################################################################
    destroy : func {
        CONFIG_DLG = 0;
        me.close();
        foreach(var l; me.listeners)
            removelistener(l);
        delete(gui.dialog, "\"" ~ me.title ~ "\"");
    },
#################################################################
    show : func {
        #return; #gui prob
        if (!CONFIG_DLG) {
            CONFIG_DLG = 1;
            me.init();
            me.create();
        }
    },
#################################################################
    select_and_load : func {
        var selector = gui.FileSelector.new
            (func (n) { CAFire.load_event_log(n.getValue()); },
             "Load Wildfire log",                    # dialog title
             "Load",                                 # button text
             ["*.xml"],                              # pattern for files
             SAVEDIR,                                # start dir
             "fire_log.xml");                        # default file name
        selector.open();
    }


};   #oh yeah, that final ; is REALLy needed    
###############################################################################

var bombable_dialog_save = func {
        #return; #gui prob
        debprint ("Bombable: iowriting, writing . . . ");
        io.write_properties(bombable_settings_file, ""~bomb_menu_pp);
}        

var init_bombable_dialog_listeners = func {
  #return; #gui prob
  #We replaced this scheme for writing the menu selections whenever they
  #are changed, to just using the 'save' button
  #what to do when any bombable setting is changed
  #setlistener(""~bomb_menu_pp, func {
  
    #the lock prevents the file from being written if we are setting/
    # changing menu values internally or setting menu defaults
    # We only want to save the menu properties when the **user**
    # makes changes.
  #  debprint ("Bombable: iowriting, checking lock . . . ");            
  #  if (!getprop(bomb_menu_save_lock)) {
  #      debprint ("Bombable: iowriting, writing . . . ");
  #      io.write_properties(bombable_settings_file, ""~bomb_menu_pp);
  #  }    
    
  #},0,2);#0,0 means (0) don't do on initial startup and (2) call listener func
  # on change of any child value

     #set listener function for main weapon power menu item 
     setlistener(""~bomb_menu_pp~"main-weapon-realism-combo", func {
    
        var weap_pow=""~bomb_menu_pp~"main-weapon-realism-combo";
        var val = getprop(weap_pow);
        
        debprint ("Updating main weapon power combo . . . ");
        
        #"Realistic", "Easy", "Super Easy", "Super-Duper Easy"
        if (val=="Ultra-realistic") {
          setprop (bomb_menu_pp~"easy-mode", 0);
          setprop (bomb_menu_pp~"super-easy-mode", 0);   
        } elsif (val=="Normal") {
          setprop (bomb_menu_pp~"easy-mode", 1);
          setprop (bomb_menu_pp~"super-easy-mode", 0);   
        } elsif (val=="Dead easy") {
          setprop (bomb_menu_pp~"easy-mode", 1);
          setprop (bomb_menu_pp~"super-easy-mode", 1);   
        } else { #value "Easier" is the default
          setprop (bomb_menu_pp~"easy-mode", 0);
          setprop (bomb_menu_pp~"super-easy-mode", 1);
        }  
        
    },1,1);#0,0 means (1) do on initial startup and (1) call listener func only when value is changed
   
   
 
   #set listener function for main weapon power menu item 
   setlistener(""~bomb_menu_pp~"ai-weapon-power-combo", func {
  
      debprint ("Updating ai weapon power combo . . . ");
      
      
      var weap_pow=""~bomb_menu_pp~"ai-weapon-power-combo";
      var val = getprop(weap_pow);
      
      if (val=="More effective") {
        setprop (bomb_menu_pp~"ai-weapon-power", 15);   
        setprop (bomb_menu_pp~"ai-aircraft-weapons-enabled", 1);
      } elsif (val=="Much more effective") {
        setprop (bomb_menu_pp~"ai-weapon-power", 22.5);
        setprop (bomb_menu_pp~"ai-aircraft-weapons-enabled", 1);
      } elsif (val=="Less effective") {
        setprop (bomb_menu_pp~"ai-weapon-power", 7.5);
        setprop (bomb_menu_pp~"ai-aircraft-weapons-enabled", 1);
      } elsif (val=="Normal") {
        setprop (bomb_menu_pp~"ai-weapon-power", 11);
        setprop (bomb_menu_pp~"ai-aircraft-weapons-enabled", 1);
      } elsif (val=="Disabled (they can't shoot at you)") {
        setprop (bomb_menu_pp~"ai-weapon-power", 0);
        setprop (bomb_menu_pp~"ai-aircraft-weapons-enabled", 0);
      } else { #value "Much less effective" is the default
        setprop (bomb_menu_pp~"ai-weapon-power", 5);
        setprop (bomb_menu_pp~"ai-aircraft-weapons-enabled", 1);
      }        
      
    
  },1,1);#0,0 means (1) do on initial startup and (1) call listener func only when value is changed


      #set listener function for AI aircraft fighting skill menu item 
   setlistener(""~bomb_menu_pp~"ai-aircraft-skill-combo", func {

      debprint ("Updating ai aircraft skill combo . . . ");
      var maneuv=""~bomb_menu_pp~"ai-aircraft-skill-combo";
      var val = getprop(maneuv);
      
      #"Realistic", "Easy", "Super Easy", "Super-Duper Easy"
      if (val=="Very skilled") {
        setprop (bomb_menu_pp~"ai-aircraft-skill-level", 5);   
        setprop (bomb_menu_pp~"ai-aircraft-attack-enabled", 1);
      } elsif (val=="Above average") {
        setprop (bomb_menu_pp~"ai-aircraft-skill-level", 4);
        setprop (bomb_menu_pp~"ai-aircraft-attack-enabled", 1);
      } elsif (val=="Below average") {
        setprop (bomb_menu_pp~"ai-aircraft-skill-level", 2);
        setprop (bomb_menu_pp~"ai-aircraft-attack-enabled", 1);
      } elsif (val=="Normal") {
        setprop (bomb_menu_pp~"ai-aircraft-skill-level", 3);
        setprop (bomb_menu_pp~"ai-aircraft-attack-enabled", 1); 
      } elsif (val=="Disabled (AI aircraft can't maneuver)") {
        setprop (bomb_menu_pp~"ai-aircraft-skill-level", 0);
        setprop (bomb_menu_pp~"ai-aircraft-attack-enabled", 0);   
      } else { #value "Unskilled" is the default
        setprop (bomb_menu_pp~"ai-aircraft-skill-level", 1);
        setprop (bomb_menu_pp~"ai-aircraft-attack-enabled", 1);
      }        
    
  },1,1);#0,0 means (1) do on initial startup and (1) call listener func only when value is changed

}

var setupBombableMenu = func {
      
      
      init_bombable_dialog_listeners ();
      
      #main bombable module is enabled by default
      if (getprop (bomb_menu_pp~"bombable-enabled") == nil )   
        props.globals.getNode(bomb_menu_pp~"bombable-enabled", 1).setBoolValue(1);
      
      #multiplayer mode enabled by default
      if (getprop (MP_share_pp) == nil )   
        props.globals.getNode(MP_share_pp, 1).setBoolValue(1);
        
        
     #fighter attack turned on by default
     if (getprop (""~bomb_menu_pp~"ai-aircraft-attack-enabled") == nil )  
        props.globals.getNode(""~bomb_menu_pp~"ai-aircraft-attack-enabled", 1).setIntValue(1);

     
     if (getprop (""~bomb_menu_pp~"ai-ground-loop-enabled") == nil )  
        props.globals.getNode(""~bomb_menu_pp~"ai-ground-loop-enabled", 1).setIntValue(1);

        
      #set these defaults
      if (getprop (""~bomb_menu_pp~"main-weapon-realism-combo") == nil )  
        props.globals.getNode(""~bomb_menu_pp~"main-weapon-realism-combo", 1).setValue("Much easier");
      if (getprop (""~bomb_menu_pp~"ai-weapon-power-combo") == nil )
        props.globals.getNode(""~bomb_menu_pp~"ai-weapon-power-combo", 1).setValue("Less effective");
      if (getprop (""~bomb_menu_pp~"ai-aircraft-skill-combo") == nil )
        props.globals.getNode(""~bomb_menu_pp~"ai-aircraft-skill-combo", 1).setValue("Unskilled");
        
      #debug default                   
      if (getprop (bomb_menu_pp~"debug") == nil )
        props.globals.getNode(bomb_menu_pp~"debug", 1).setIntValue(0);

      #flack is default off because it seems to sometimes cause FG crashes
      #Update now default on because it seems fine
      if (getprop (""~trigger1_pp~"flack"~trigger2_pp) == nil )
                 props.globals.getNode(""~trigger1_pp~"flack"~trigger2_pp, 1).setBoolValue(1);

      if (getprop (""~trigger1_pp~"ai-weapon-fire-visual"~trigger2_pp) == nil )
                 props.globals.getNode(""~trigger1_pp~"ai-weapon-fire-visual"~trigger2_pp, 1).setBoolValue(1);


            

      foreach (var smokeType; [
                ["fire",88, 3600], 
                ["jetcontrail", 77, -1],
                ["smoketrail", 55, -1],         
                ["pistonexhaust", 15, -1],
                ["damagedengine",  55, -1],
                ["flare",66,3600],
                ] ) {
      
      #trigger is the overall flag for that type of smoke/fire
      # for Bombable as a whole
      # burning is the flag as to whether that effect is turned on
      # for the main aircraft      
        
          
             props.globals.getNode(""~life1_pp~smokeType[0]~burning_pp, 1).setBoolValue(0);
             if (getprop (""~trigger1_pp~smokeType[0]~trigger2_pp) == nil )
                 props.globals.getNode(""~trigger1_pp~smokeType[0]~trigger2_pp, 1).setBoolValue(1);
      	     props.globals.getNode(""~life1_pp~smokeType[0]~life2_pp, 1).setDoubleValue(smokeType[1]);
             props.globals.getNode(""~burntime1_pp~smokeType[0]~burntime2_pp, 1).setDoubleValue(smokeType[2]);
      
               
      } 
    
      init_bombable_dialog();      
      #the previously attempted "==nil" trick doesn't work because this io.read routine
      # leaves unchecked values as 'nil'
      # so we set our defaults first & then load the file.  Anything that wasn't set by 
      # the file just remains as our default.
      #   
      # Now, read the menu default file:
      debprint ("Bombable: ioreading . . . ");                 
      var target = props.globals.getNode(""~bomb_menu_pp);
      io.read_properties(bombable_settings_file, target);

      

      
    
}

#####################################################
# FUNCTION calcPilotSkill
# returns the skill level of the AI pilot
# adjusted for the pilot individual skill level AND
# the current level of damage
# 

var calcPilotSkill = func ( myNodeName ) {
    #skill ranges 0-5; 0=disabled, so 1-5;
    var skill=getprop (bomb_menu_pp~"ai-aircraft-skill-level");
    if (skill==nil) skill=0;  
  	var skillMult=1;
  	#pilotSkill is a rand +/-1 in skill level per individual pilot
  	# so now skill ranges 0-6  	
  	var pilotSkill = getprop(""~myNodeName~"/bombable/attack-pilot-ability");
  	if (pilotSkill==nil) pilotSkill=0;
  	skill+=pilotSkill;
  	
  	#ability to maneuever goes down as attack fuel reserves are depleted
  	var fuelLevel=stores.fuelLevel (myNodeName);
  	if (fuelLevel<.2) skill *= fuelLevel/ 0.2;
 
  	
  	var damage = getprop(""~myNodeName~"/bombable/attributes/damage");
    
    #skill goes down to 0 as damage goes from 80% to 100%
    if (damage > 0.8) skill *= (1 - damage)/ 0.2;
    
    return skill;
                    
}  

##########################################################
# FUNCTION trueAirspeed2indicatedAirspeed
# Give a node name & true airspeed, returns the indicated airspeed
# (using the elevation of the AI object for the calculation)
# 
# The formula IAS=TAS* (1 + .02 * alt/1000) is a rule-of-thumb 
# approximation for IAS but about the best we can do in simple terms 
# since we don't have the temperature or pressure of the AI aircraft 
# current altitude easily available.
# 
# TODO: We should really use IAS for more of the AI aircraft speed limits
# & calculations, but stall speed is likely most crucial.  For instance,
# VNE (max allowed speed) seems more related to TAS for most AC.

var trueAirspeed2indicatedAirspeed = func (myNodeName="", trueAirspeed_kt=0 ) {

      currAlt_ft = getprop(""~myNodeName~"/position/altitude-ft");
      return trueAirspeed_kt * ( 1 + .02 * currAlt_ft/1000); 

}

####################################################
#return altitude (in feet) of given lat/lon

var elev = func (lat, lon) {

  var info = geodinfo(lat, lon);
  
  if (info != nil) {
      var alt_m=info[0];
      if (alt_m==nil) alt_m=0; 
      return alt_m/feet2meters; #return the altitude in feet
  } else  return 0;
  
}
			
###############################################################################
# MP messages
# directly based on similar functions in wildfire.nas
# 

var damage_msg = func (callsign, damageAdd, damageTotal, smoke=0, fire=0, messageType=1) {
  if (!getprop(MP_share_pp)) return;
  if (!getprop (MP_broadcast_exists_pp)) return;
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
  
  n=0;
  
  #bits.switch(n,1, checkRange(smoke,0,1,0 ));  # !! makes sure it's a boolean value
  #bits.switch(n,2, checkRange(fire,0,1,0 )); #can send up to 7 bits in a byte this way

  
  msg=sprintf ("%6s", callsign) ~ 
        Binary.encodeByte(messageType) ~ 
        Binary.encodeDouble(damageAdd) ~ 
        Binary.encodeDouble(damageTotal) ~ 
        Binary.encodeByte(smoke) ~
        Binary.encodeByte(fire);
  
  #too many messages overwhelm the system.  So we set a lock & only send messages
  # every 5 seconds or so (lockWaitTime); at the end we send the final message 
  # (which has the final damage percentage)  
  # of any that were skipped in the meanwhile    
  lockName=""~callsign~messageType;
  
  lock=props.globals.getNode("/bombable/locks/"~lockName~"/lock", 1).getValue();
  if (lock==nil or lock=="") lock=0;
  
  masterLock=props.globals.getNode("/bombable/locks/masterLock", 1).getValue();
  if (masterLock==nil or masterLock=="") masterLock=0;
  
  currTime=systime();
  
  #We can send 1 message per callsign & per message type, per lockWaitTime 
  # seconds.  It sets a lock to prevent messages being sent in the meanwhile.
  # It sets a timer to send a cumulative damage message at the end of the 
  # lock time to give a single update for damage in the meanwhile.
  # As a failsafe it also saves system time in the lock & any new
  # damage messages coming through after that lockWaitTime seconds are 
  # allowed to go forward.   
  # For vitally important messages (like master reset) we can set a masterLock
  # and no other messages can go out during that time.
  # This is abit of a kludge.   For real we should queue up messages &
  # send them out at a rate no faster than say 1/2 as fast as the rate
  # mpreceive checks for new messages.                        
  if ((currTime - masterLock > masterLockWaitTime) and (lock==nil or lock=="" or lock==0 or currTime - lock > lockWaitTime)) {
    
    lockNum=lockNum+1;
    props.globals.getNode("/bombable/locks/"~lockName~"/lock", 1).setDoubleValue(currTime);
    settimer (func {
        lock=getprop ("/bombable/locks/"~lockName~"/lock");
        msg2=getprop ("/bombable/locks/"~lockName~"/msg");
        setprop ("/bombable/locks/"~lockName~"/lock", 0);
        setprop ("/bombable/locks/masterLock", 0);
        setprop ("/bombable/locks/"~lockName~"/msg", "");
        if (msg2!=nil and msg2 != ""){
          mpsend(msg2);
          debprint ("Bombable: Sending delayed message "~msg);
        }
    }, lockWaitTime);
        
    return msg
    
        
  } else {
      setprop ("/bombable/locks/"~lockName~"/msg", msg);
      return nil;
  }

}

###############################################################################
# reset_msg - part of MP messages
# 

var reset_msg = func () {
  if (!getprop(MP_share_pp)) return "";
  if (!getprop (MP_broadcast_exists_pp)) return "";
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
  
  n=0;
  
  #bits.switch(n,1, checkRange(smoke,0,1,0 ));  # !! makes sure it's a boolean value
  #bits.switch(n,2, checkRange(fire,0,1,0 )); #can send up to 7 bits in a byte this way
  
  callsign=getprop ("/sim/multiplay/callsign");
  props.globals.getNode("/bombable/locks/masterLock", 1).setDoubleValue(systime());  
  #messageType=2 is the reset message
  return sprintf ("%6s", callsign) ~ 
      Binary.encodeByte(2);
}

var parse_msg = func (source, msg) {
  if (!getprop(MP_share_pp)) return;
  if (!getprop (MP_broadcast_exists_pp)) return;
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;    
  debprint("Bombable: typeof source: ", typeof(source));    
  debprint ("Bombable: source: ", source, " msg: ",msg);   
  var ourcallsign=getprop ("/sim/multiplay/callsign"); 
  var p = 0;
  var msgcallsign = substr(msg, 0, 6);
  p = 6;
  
  var type = Binary.decodeByte(substr(msg, p));
  p += Binary.sizeOf["byte"];
  #debprint ("msgcallsign:"~ msgcallsign," type:"~ type);
 
  #not our callsign and type !=2, we ignore it & return (type=2 broadcasts to 
  #*everyone* that their callsign is re-setting, so we always listen to that)
  if ((sprintf ("%6s", msgcallsign) != sprintf ("%6s", ourcallsign)) and 
     type != 2 and type != 3 ) return;
 
 
  
  #damage message
  if (type == 1) {
    var damageAdd = Binary.decodeDouble(substr(msg, p));
    p += Binary.sizeOf["double"];
    var damageTotal = Binary.decodeDouble(substr(msg, p));
    p += Binary.sizeOf["double"];
    var smokeStart = Binary.decodeByte(substr(msg, p));
    p += Binary.sizeOf["byte"];
    var fireStart = Binary.decodeByte(substr(msg, p));
    p += Binary.sizeOf["byte"];
      
    debprint ("damageAdd:",damageAdd," damageTotal:",damageTotal," smoke:",smokeStart," fire:", fireStart);  
      
    mainAC_add_damage (damageAdd, damageTotal, "weapons", "Hit by weapons!" );
    
  }
  
  #reset message for callsign
  elsif (type == 2) {
  
   #ai_loc="/ai/models";
   #var mp_aircraft = props.globals.getNode(ai_loc).getChildren("multiplayer");
   #foreach (mp;mp_aircraft) { #mp is the node of a multiplayer AI aircraft
   
   #    mp_callsign=mp.getNode("callsign").getValue();
   #    mp_childname=mp.getName();
   #    mp_index=mp.getIndex();
   #    mp_name=ai_loc~"/"~mp_childname~"["~mp_index~"]";
   #    mp_path=cmdarg().getPath(mp);
   #    debprint ("Bombable: mp_path=" ~mp_path);
   
         mp_name=source;   
         debprint ("Bombable: Resetting fire/damage for - name: ", source, " callsign: "~string.trim(msgcallsign) );
       
   #    if (sprintf ("%6s", mp_callsign) == sprintf ("%6s", msgcallsign)) { 
       
         #blow away the locks for MP communication--shouldn't really
         # be needed--just a little belt & suspendors things here
         # to make sure that no old damage (prior to the reset) is sent
         # to the aircraft again after the reset, and that none of the 
         # locks are stuck.                            
         props.globals.getNode("/bombable").removeChild("locks",0);
         resetBombableDamageFuelWeapons(source);
         msg= string.trim(msgcallsign)~" is resetting; damage reset to 0% for "~string.trim(msgcallsign);
         debprint ("Bombable: "~msg);
         targetStatusPopupTip (msg, 30);
         
         
    #  }
       
   #}
   


  }
  #update of callsign's current damage, smoke, fire situation
  elsif (type == 3) {

   #  ai_loc="/ai/models";
   #var mp_aircraft = props.globals.getNode(ai_loc).getChildren("multiplayer");
   #foreach (mp;mp_aircraft) { #mp is the node of a multiplayer AI aircraft
   
   #    mp_callsign=mp.getNode("callsign").getValue();
   #    mp_childname=mp.getName();
   #   mp_index=mp.getIndex();
   #    mp_name=ai_loc~"/"~mp_childname~"["~mp_index~"]";
   #    mp_path=cmdarg().getPath(mp);
       
       
   #    if (sprintf ("%6s", mp_callsign) == sprintf ("%6s", msgcallsign)) { 
          debprint ("Bombable: Updating fire/damage from - name: ", source ," callsign: "~string.trim(msgcallsign) );
          var damageAdd = Binary.decodeDouble(substr(msg, p));
          p += Binary.sizeOf["double"];
          var damageTotal = Binary.decodeDouble(substr(msg, p));
          p += Binary.sizeOf["double"];
          var smokeStart = Binary.decodeByte(substr(msg, p));
          p += Binary.sizeOf["byte"];
          var fireStart = Binary.decodeByte(substr(msg, p));
          p += Binary.sizeOf["byte"];
          
          mp_update_damage (source, damageAdd, damageTotal, smokeStart, fireStart, msgcallsign );      
          
      #}
       
   # }



  }  
  elsif (type == 4) {
    var pos    = Binary.decodeCoord(substr(msg, 6));
    var radius = Binary.decodeDouble(substr(msg, 36));
    resolve_foam_drop(pos, radius, 0, 0);
  }  
}

####################################################
#timer function, every 1.5 to 2.5 seconds, adds damage if on fire
# TODO: This seems to be causing stutters.  We can separate out a separate
# loop to update the fire sizes and probably do some simplification of the
# add_damage routines.
# 
var fire_loop = func(id, myNodeName="") {
  if (myNodeName=="") myNodeName="";
  var loopid = getprop(""~myNodeName~"/bombable/loopids/fire-loopid"); 
	id == loopid or return;
  
  #Set the timer function here at the top 
  #   so if there is some runtime error in the code
  #   below the timer function still continues to run   
  var fireLoopUpdateTime_sec=3;
  # add rand() so that all objects dont do this function simultaneously
  #debprint ("fire_loop starting");   
	settimer(func { fire_loop(id, myNodeName); }, fireLoopUpdateTime_sec - 0.5 + rand());
  	
	node= props.globals.getNode(myNodeName);
  type=node.getName();
  
  if(getprop(""~myNodeName~"/bombable/fire-particles/fire-burning")) {
	  var myFireNodeName = getprop(""~myNodeName~"/bombable/fire-particles/fire-particles-model");
	

  	#we have one single property to control the startsize & endsize
  	#of ALL fire-particles active at one time. This is a bit fakey but saves on processor time.
  	#  The idea here is to change
  	# the values of the start/endsize randomly and fairly quickly so the
  	# various smoke columns don't all look like clones of each other
  	# each smoke column only puts out particles 2X per second so 
  	# if the sizes are changed more often than that they can affect only
  	# some of the smoke columns independently.            	
    var smokeEndsize = rand()*100+50;
  	setprop ("/bombable/fire-particles/smoke-endsize", smokeEndsize);
  	
  	var smokeEndsize = rand()*125+60;
  	setprop ("/bombable/fire-particles/smoke-endsize-large", smokeEndsize);
  	
  	var smokeEndsize = rand()*75+33;
  	setprop ("/bombable/fire-particles/smoke-endsize-small", smokeEndsize);
  	
  	var smokeEndsize = rand()*25+9;
  	setprop ("/bombable/fire-particles/smoke-endsize-very-small", smokeEndsize);
  	
  	
    var smokeStartsize=rand()*10 + 5;
  	
    #occasionally make a really BIG explosion
  	if (rand()<.02/fireLoopUpdateTime_sec)  {
  	
        settimer (func {setprop ("/bombable/fire-particles/smoke-startsize", smokeStartsize); }, 0.1);#turn the big explosion off quickly so it only affects a few of the fires for a moment--they put out smoke particles 4X/second
        smokeStartsize = smokeStartsize * rand() * 15 + 100; #make the occasional really big explosion
    }
         
  	setprop ("/bombable/fire-particles/smoke-startsize", smokeStartsize);
  	setprop ("/bombable/fire-particles/smoke-startsize-small", smokeStartsize * (rand()/2 + 0.5));
  	setprop ("/bombable/fire-particles/smoke-startsize-very-small", smokeStartsize * (rand()/8 + 0.2));
  	setprop ("/bombable/fire-particles/smoke-startsize-large", smokeStartsize* (rand()*4 + 1));
  	
  	#damageRate_percentpersecond = getprop (""~myNodeName~"/bombable/attributes/vulnerabilities/fireDamageRate_percentpersecond");
  	
  	damageRate_percentpersecond = attributes[myNodeName].vulnerabilities.fireDamageRate_percentpersecond;
  	
  	if (damageRate_percentpersecond==nil) damageRate_percentpersecond=0;
  	if (damageRate_percentpersecond==0) damageRate_percentpersecond=0.1;
  	
  	# The object is burning, so we regularly add damage.	
  	# Have to do it differently if it is the main aircraft ("")
  	if (myNodeName=="") {
  	mainAC_add_damage( damageRate_percentpersecond/100 * fireLoopUpdateTime_sec,0, "fire", "Fire damage!" );
    } 
    #we don't add damage to multiplayer--we let the remote object do it & send 
    #  it back to us
    else {        	
  	 if (type != "multiplayer") add_damage( damageRate_percentpersecond/100 * fireLoopUpdateTime_sec , myNodeName,"nonweapon" );
    } 
	}
                                                                                      

}

##########################################################
#Puts myNodeName right at ground level, explodes, sets up 
#for full damage & on-ground trigger to make it stop real fast now
#
var hitground_stop_explode = func (myNodeName, alt) {
  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  var vuls = attributes[myNodeName].vulnerabilities;	
  

   startFire( myNodeName ); #if it wasn't on fire before it is now
   #debprint ("Bombable: setprop 4256");
   setprop (""~myNodeName~"/position/altitude-ft",  alt  );
   setprop (""~myNodeName~"/bombable/on-ground",  1 ); #this affects the slow-down system which is handled by add-damage, and will stop any forward movement very quickly
   add_damage(1, myNodeName, "nonweapon");  #and once we have buried ourselves in the ground we are surely dead; this also will stop any & all forward movement
         
   #check if this object has exploded already 
   exploded= getprop (""~myNodeName~"/bombable/exploded" );
   
   #if not, explode for ~3 seconds
   if ( exploded==nil or !exploded ){      
     #and we cover our tracks by making a really big explosion momentarily
     #if it hit the ground that hard it's justified, right?
     if (vuls.explosiveMass_kg<0) vuls.explosiveMass_kg=1;
     lnexpl= math.ln (vuls.explosiveMass_kg/10);      
     var smokeStartsize = rand()*lnexpl*20 + 30;
     setprop ("/bombable/fire-particles/smoke-startsize", smokeStartsize);
     setprop ("/bombable/fire-particles/smoke-startsize-small", smokeStartsize * (rand()/2 + 0.5));
     setprop ("/bombable/fire-particles/smoke-startsize-very-small", smokeStartsize * (rand()/8 + 0.2));
     setprop ("/bombable/fire-particles/smoke-startsize-large", smokeStartsize * (rand()*4 + 1));
     
     #explode for, say, 3 seconds but then we're done for this object
     settimer (   func {setprop(""~myNodeName~"/bombable/exploded" , 1 ); }, 3 + rand() );
   }

}          

var addAltitude_ft = func  (myNodeName, altAdd_ft=40 , time=1 ) {
   
   var loopTime=0.033;
   
   elapsed = getprop(""~myNodeName~"/position/addAltitude_elapsed");
   if (elapsed==nil) elapsed=0;
   elapsed+= loopTime;
   #debprint ("Bombable: setprop 4257");
   setprop(""~myNodeName~"/position/addAltitude_elapsed", elapsed);
   
   
   
   currAlt_ft = getprop (""~myNodeName~"/position/altitude-ft");
   
   #if (elapsed==0) setprop (""~myNodeName~"/position/addAltitude_starting_alt_ft", currAlt_ft ) 
   #else var startAlt_ft=getprop (""~myNodeName~"/position/addAltitude_starting_alt_ft");  
   
   #debprint ("Bombable: setprop 1284");
   setprop (""~myNodeName~"/position/altitude-ft", currAlt_ft+altAdd_ft*loopTime/time);
   
   #debprint ("Bombable: setprop 1287");
   if (elapsed < time) settimer (func { addAltitude_ft (myNodeName,altAdd_ft,time)}, loopTime);
   
   else setprop(""~myNodeName~"/position/addAltitude_elapsed", 0 ); 

}


######################################
# FUNCTION setVerticalSpeed
# Changes to the new target vert speed but gradually over a few steps
# using settimer
# 
var setVerticalSpeed = func (myNodeName, targetVertSpeed_fps=70, maxChange_fps=25, iterations=4, time=.05) {

  curr_vertical_speed_fps=getprop (""~myNodeName~"/velocities/vertical-speed-fps");            
  var new_vertical_speed_fps=checkRange (targetVertSpeed_fps, curr_vertical_speed_fps-maxChange_fps, curr_vertical_speed_fps+maxChange_fps, targetVertSpeed_fps);                        
  setprop (""~myNodeName~"/velocities/vertical-speed-fps",  new_vertical_speed_fps);
  iterations -=1;
  
  if (iterations>-0) {
      settimer (func {
          setVerticalSpeed (myNodeName, targetVertSpeed_fps, maxChange_fps, iterations, time);
      } , time);
  }    

}            

###################################################
#ground_loop
#timer function, every (0.5 to 1.5 * updateTime_s) seconds, to keep object at 
# ground level 
# or other specified altitude above/below ground level, and at a 
# reasonable-looking pitch. length_m & width_m are distances (in meters) 
# needed to clear the object and find open earth on either side and front/back.
# damagealtadd is the total amount to subtract from the normal the altitude above ground level (in meters) as 
# the object becomes damaged--say a sinking ship or tires flattening on a 
# vehicle.
# damageAltMaxRate is the max rate to allow the object to rise or sink
# as it becomes disabled
# TODO: This is one of the biggest framerate sucks in Bombable.  It can probably 
# be optimized in many ways.
var ground_loop = func( id, myNodeName ) {
    var loopid = getprop(""~myNodeName~"/bombable/loopids/ground-loopid"); 
  	id == loopid or return;   	                       

    #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
    var updateTime_s=attributes[myNodeName].updateTime_s;
  
    #reset the timer loop first so we don't lose it entirely in case of a runtime
  	# error or such	
  	#    add rand() so that all objects don't do this function simultaneously
  	settimer(func { ground_loop(id, myNodeName)}, (0.5 + rand())*updateTime_s );

  	#Allow this function to be disabled via menu/it can kill framerate at times
    if (! getprop ( bomb_menu_pp~"ai-ground-loop-enabled") or ! getprop(bomb_menu_pp~"bombable-enabled") ) return;

    #debprint ("ground_loop starting");  

    node= props.globals.getNode(myNodeName);
    type=node.getName();

    #var alts = b.getNode("altitudes").getValues();	
    #var dims = b.getNode("dimensions").getValues();
    #var vels = b.getNode("velocities").getValues(); 
    var alts = attributes[myNodeName].altitudes;	
    var dims = attributes[myNodeName].dimensions;
    var vels = attributes[myNodeName].velocities; 
    var onGround= getprop (""~myNodeName~"/bombable/on-ground"); 
    if (onGround==nil) onGround=0;  	
    
    # If you get too close in to the object, FG detects the elevation of the top of the object itself
    # rather than the underlying ground elevation. So we go an extra FGAltObjectPerimeterBuffer_m 
    #meters out from the object
    # just to be safe.  Otherwise objects climb indefinitely, always trying to get on top of themselves
    # Sometimes needed in _m, sometimes _ft, so we need both . . .  
    var FGAltObjectPerimeterBuffer_m = 2.5;
    var FGAltObjectPerimeterBuffer_ft = FGAltObjectPerimeterBuffer_m/feet2meters; 
    
    var thorough = rand()<1/5; # to save FR we only do it thoroughly sometimes
    if (onGround) thorough=0; #never need thorough when crashed
    
    #Update altitude to keep moving objects at ground level the ground	
    var currAlt_ft= getprop(""~myNodeName~"/position/altitude-ft"); #where the object is, in feet
  	var lat = getprop(""~myNodeName~"/position/latitude-deg");
    var lon = getprop(""~myNodeName~"/position/longitude-deg");
    var heading = getprop(""~myNodeName~"/orientation/true-heading-deg");
    var speed_kt = getprop(""~myNodeName~"/velocities/true-airspeed-kt");
    var damageValue = getprop(""~myNodeName~"/bombable/attributes/damage");
    var damageAltAddPrev_ft = getprop(""~myNodeName~"/bombable/attributes/damageAltAddCurrent_ft");
    if (damageAltAddPrev_ft == nil) damageAltAddPrev_ft=0;
    var damageAltAddCumulative_ft = getprop(""~myNodeName~"/bombable/attributes/damageAltAddCumulative_ft");
    if (damageAltAddCumulative_ft == nil) damageAltAddCumulative_ft=0;
    
    if (lat==nil) {
          lat=0; 
          debprint ("Bombable: Lat=NIL, ground_loop ", myNodeName);
    }
    if (lon==nil) {
          lon=0; 
          debprint ("Bombable: Lon=NIL, ground_loop ", myNodeName);
    }

  
  
  
    #calculate the altitude behind & ahead of the object, this determines the pitch angle and helps determine the overall ground level at this spot
    #Go that extra amount, FGAltObjectPerimeterBuffer_m, out from the actual length to keep FG from detecting the top of the
    #object as the altitude.  We need ground altitude here.   
    # You can't just ask for elev at the object's current position or you'll get
    # the elev at the top of the object itself, not the ground . . .            
    var GeoCoord = geo.Coord.new();
    GeoCoord.set_latlon(lat, lon);
    #debprint ("Bombable: GeoCoord.apply_course_distance(heading, dims.length_m/2); ",heading, " ", dims.length_m/2 );
    GeoCoord.apply_course_distance(heading, dims.length_m/2 + FGAltObjectPerimeterBuffer_m);    #frontreardist in meters
    toFrontAlt_ft=elev (GeoCoord.lat(), GeoCoord.lon()  ); #in feet
    
    #This loop is one of our biggest framerate sucks and so if we're an undamaged
    # aircraft way above our minimum AGL we're just going to skip it entirely.    
    if (type=="aircraft" and damageValue < 0.95 and (currAlt_ft - toFrontAlt_ft) > 3* alts.minimumAGL_ft) return;
    
    
    if (thorough) {
      GeoCoord.apply_course_distance(heading+180, dims.length_m + 2 * FGAltObjectPerimeterBuffer_m );
      toRearAlt_ft=elev (GeoCoord.lat(), GeoCoord.lon()  ); #in feet    
    } else {
       toRearAlt_ft=toFrontAlt_ft;
    }
    
     
    #debprint ("oFront:", toFrontAlt_ft);
    if (type=="aircraft" and ! onGround ) { 
           #poor man's look-ahead radar                                            
  
           GeoCoord.apply_course_distance(heading, dims.length_m + speed_kt * 0.5144444 * 10 );
             
             var radarAheadAlt_ft=elev (GeoCoord.lat(), GeoCoord.lon()  ); #in feet
             
           
           #debprint ("result: "~ radarAheadAlt_ft);
             # our target altitude (for aircraft purposes) is the greater of the
             # altitude immediately in front and the altitude from our
             # poor man's lookahead radar. (ie, up to 2 min out at current 
             # speed).  If the terrain is rising we add 300 to our taret
             # alt just to be on the safe side.                 
             # But if we're crashing, we don't care about
             # what is ahead.                                                 
           lookingAheadAlt_ft=toFrontAlt_ft;
           #debprint ("tofrontalt ft: ", toFrontAlt_ft, " radaraheadalt ", radarAheadAlt_ft);
           # Use the radar lookahead altitude if
           #  1. higher than elevation fo current location
           #  2. not damaged
           #  3. we'll end up below our minimumAGL if we continue at 
           #  4. current altitude                                                       
           if ( radarAheadAlt_ft > toFrontAlt_ft and  (damageValue < 0.8 ) 
               and (radarAheadAlt_ft + alts.minimumAGL_ft > currAlt_ft )  )        
               lookingAheadAlt_ft = radarAheadAlt_ft;
               
           #if we're low to the ground we add this extra 300 ft just to be safe           
           if (currAlt_ft-radarAheadAlt_ft < 500) 
                  lookingAheadAlt_ft +=300;
    } else {
           lookingAheadAlt_ft =toFrontAlt_ft;
    }
    
    # if it's damage we always get the pitch angle etc as that is how we force it down. 
    # but if it's on the ground, we don't care and all these geo.Coords & elevs really kill FR.     
    if (thorough or ( damageValue > 0.8 and ! onGround ) ) { 
      pitchangle1_deg = rad2degrees * math.atan2(toFrontAlt_ft - toRearAlt_ft, dims.length_ft + 2* FGAltObjectPerimeterBuffer_ft ); #must convert this from radians to degrees, thus the 180/pi
       
      pitchangle_deg=pitchangle1_deg;
    
    
      #figure altitude of ground to left & right of object to determine roll &
      #to help in determining altitude  
       
      var GeoCoord2 = geo.Coord.new();
      GeoCoord2.set_latlon(lat, lon);
      #go that extra amount out from the actual width to keep FG from detecting the top of the
      #object as the altitude.  We need ground altitude here. FGAltObjectPerimeterBuffer_m
      GeoCoord2.apply_course_distance(heading+90, dims.width_m/2 + FGAltObjectPerimeterBuffer_m);  #sidedist in meters
      toRightAlt_ft=elev (GeoCoord2.lat(), GeoCoord2.lon()  ); #in feet
      GeoCoord2.apply_course_distance(heading-90, dims.width_m + 2*FGAltObjectPerimeterBuffer_m );
      toLeftAlt_ft=elev (GeoCoord2.lat(), GeoCoord2.lon()  ); #in feet
      rollangle_deg = 90 - rad2degrees * math.atan2(dims.width_ft + 2 * FGAltObjectPerimeterBuffer_ft, toLeftAlt_ft - toRightAlt_ft ); #must convert this from radians to degrees, thus the 180/pi
         
      #in CVS, taking the alt of an object's position actually finds the top
      #of that particular object.  So to find the alt of the actual landscape
      # we do ahead, behind, to left, to right of object & take the average.
      #luckily this also helps us calculate the pitch of the slope,
      #which we need to set pitch & roll,  so little is 
      #lost 
      alt_ft = (toFrontAlt_ft + toRearAlt_ft + toLeftAlt_ft + toRightAlt_ft) / 4; #in feet
    } else {
      alt_ft = toFrontAlt_ft;
      toLeftAlt_ft = toFrontAlt_ft;
      toRightAlt_ft = toFrontAlt_ft;
    }
    
    #The first time this is called just initializes all the altitudes and exit
    if ( alts.initialized != 1 ) {
       var initial_altitude_ft= getprop (""~myNodeName~"/position/altitude-ft");
       if (initial_altitude_ft<alt_ft + alts.wheelsOnGroundAGL_ft +  alts.minimumAGL_ft) {
            initial_altitude_ft = alt_ft + alts.wheelsOnGroundAGL_ft +  alts.minimumAGL_ft;
       }
       if (initial_altitude_ft>alt_ft + alts.wheelsOnGroundAGL_ft +  alts.maximumAGL_ft) { 
            initial_altitude_ft = alt_ft + alts.wheelsOnGroundAGL_ft +  alts.maximumAGL_ft;
       }
        
       target_alt_AGL_ft=initial_altitude_ft - alt_ft - alts.wheelsOnGroundAGL_ft;
       
       debprint ("Bombable: Initial Altitude: "~ initial_altitude_ft~ " target AGL: "~target_alt_AGL_ft~ " object="~ myNodeName);
       debprint ("Bombable: ", alt_ft, " ", toRightAlt_ft, " ",toLeftAlt_ft, " ",toFrontAlt_ft," ", toLeftAlt_ft, " ", alts.wheelsOnGroundAGL_ft);
       
       #debprint ("Bombable: setprop 1430");
       setprop (""~myNodeName~"/position/altitude-ft", initial_altitude_ft );
       setprop (""~myNodeName~"/controls/flight/target-alt",  initial_altitude_ft);
       #debprint ("1349 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
       #set target AGL here. This way the aircraft file can simply set altitude
       # limits for the craft while the scenario files sets the specific altitude
       # target for a specific plane in a specific scenario          
       #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");       

       #b.getNode("altitudes/targetAGL_ft", 1).setDoubleValue(target_alt_AGL_ft);
       #b.getNode("altitudes/targetAGL_m", 1).setDoubleValue(target_alt_AGL_ft*feet2meters);
       #b.getNode("altitudes/initialized", 1).setBoolValue(1); 

       alts.targetAGL_ft=target_alt_AGL_ft;
       alts.targetAGL_m=target_alt_AGL_ft*feet2meters;
       alts.initialized=1; 
      
       return;
    
    
    }
     
    var objectsLowestAllowedAlt_ft =alt_ft + alts.wheelsOnGroundAGL_ft + alts.crashedAGL_ft;
    #debprint (" objectsLowestAllowedAlt_ft=", objectsLowestAllowedAlt_ft);
    
    if (onGround){
       #go to object's resting altitude
       
       #debprint ("Bombable: setprop 1457");
       setprop (""~myNodeName~"/position/altitude-ft", objectsLowestAllowedAlt_ft );
       setprop (""~myNodeName~"/controls/flight/target-alt",  objectsLowestAllowedAlt_ft);
       #debprint ("1373 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
       
        #all to a complete stop
        setprop(""~myNodeName~"/controls/tgt-speed-kt", 0);
        setprop(""~myNodeName~"/controls/flight/target-spd", 0);    
        setprop(""~myNodeName~"/velocities/true-airspeed-kt", 0); 
  
        #we don't even really need the timer any more, since this object
        #is now exploded to heck & stopped also.  But just in case . . .
  
        #and that's it
        return;
    
    }
    #our target altitude for normal/undamaged forward movement
    #this isn't based on our current altitude but the results of our 
    # "lookahead radar" to provide the base altitude
    # However as the craft is more damaged it loses its ability to do this 
    # (see above: lookingAheadAlt just becomes the same as toFrontAlt)       
    targetAlt_ft = lookingAheadAlt_ft + alts.targetAGL_ft + alts.wheelsOnGroundAGL_ft;
    #debprint ("laa ", lookingAheadAlt_ft, " tagl ", alts.targetAGL_ft, " awog ", alts.wheelsOnGroundAGL_ft); 
    
    
    fullDamageAltAdd_ft =   (alt_ft+alts.crashedAGL_ft +alts.wheelsOnGroundAGL_ft) - currAlt_ft; #amount we should add to our current altitude when fully crashed.  This is to get the object to "full crashed position", ie, on the ground for an aircraft, fully sunk for a ship, etc.
  
          
   #now calculate how far to force the thing down if it is crashing/damaged
   if ( damageValue > 0.8  )  {
      damageAltAddMax_ft= (damageValue) * fullDamageAltAdd_ft; #max altitude amount to add to altitude to this object based on its current damage.
      #
      #Like fullDamageAltAdd & damageAltAddPrev this should always be zero
      #or negative as everything on earth falls or sinks when it loses
      #power. And assuming that simplifies calculations immensely.
      
      #The altitude the object should be at, based on damagealtAddMax & the 
      #ground level:
      shouldBeAlt=currAlt_ft + damageAltAddMax_ft;
      #debprint ("shouldBeAlt ", shouldBeAlt);
  
      #debprint ( "alt=", alt_ft, " currAlt_ft=",currAlt_ft, " fulldamagealtadd", fullDamageAltAdd_ft," damagealtaddmax", damageAltAddMax_ft, " damagevalue", damageValue," ", myNodeName );
      
      #debprint ("shouldBeAlt=oldalt+ alts.wheelsOnGroundAGL_ft + damageAltAddMax; ",
      #   shouldBeAlt, " ", oldalt, " ", alts.wheelsOnGroundAGL_ft, " ", damageAltAddMax  ); 
      
      #limit amount of sinkage to damageAltMaxRate in one hit/loop--otherwise it just goes down too fast, not realistic.  This is basically like the terminal
      # velocity for this type of object.    
      damageAltMaxPerCycle_ft = -abs(vels.damagedAltitudeChangeMaxRate_meterspersecond*updateTime_s/feet2meters);
      
      
      
      #move 10% more than previous or if no previous, start at 1% the max rate
      #making sure to move in the right direction! (using sgn of damageAltAdd)  
      if (damageAltAddPrev_ft != 0) damageAltAddCurrent_ft = -abs((1 + 0.1*updateTime_s) * damageAltAddPrev_ft);
      else damageAltAddCurrent_ft=- abs(0.01*damageAltMaxPerCycle_ft);  
      
      # make sure this is not bigger than the max rate, if so only change
      #it by the max amount allowed per cycle
      if ( abs( damageAltAddCurrent_ft ) > abs(damageAltMaxPerCycle_ft ) ) damageAltAddCurrent_ft =  damageAltMaxPerCycle_ft;  
      
      #Make sure we're not above the max allowed altitude change for this damage level; if so, cut it off
      if ( abs(damageAltAddCurrent_ft) > abs(damageAltAddMax_ft) ) {  
             damageAltAddCurrent_ft =  damageAltAddMax_ft;
      }         
    
                        
       #debprint ( " damageAltAddMax=", damageAltAddMax, " damageAltMaxRate=",  
       #debprint ("damageAltAddCurrent_ft ", damageAltAddCurrent_ft);
       
    
      
      
   } else {
      damageAltAddCurrent_ft=0;
   }



    
   #if the thing is basically as low as allowed by crashedAGL_m
   # we consider it "on the ground" (for an airplane) or 
   # completely sunk (for a ship) etc. 
   # If it is going there at any speed we consider it crashed
   # into the ground. When this 
   # property is set to true then the speed will slow quite dramatically.
   # This allows for example airplanes to continue forward movement
   # in the air but skid to a sudden halt when hitting the ground.
   #
   # alts.wheelsOnGroundAGL_ft + damageAltAdd = the altitude (AGL) the object should be at when 
   # finished crashing, sinking, etc.        
   # It's not that easy to determine if an object crashes--if an airplane
   # hits the ground it crashes but tanks etc are always on the ground        
   noPitch=0;
   if (type=="aircraft" and (
            (damageValue > 0.8 and ( currAlt_ft <= objectsLowestAllowedAlt_ft and speed_kt > 20 ) 
            or ( currAlt_ft <= objectsLowestAllowedAlt_ft-5)) 
            or (damageValue == 1 and currAlt_ft <= objectsLowestAllowedAlt_ft) )
      ) hitground_stop_explode(myNodeName, alt_ft);
    
    

   #if we are dropping faster than the current slope (typically because
   # we are an aircraft diving to the ground because of damage) we 
   # make the pitch match that angle, even if it more acute than the
   # regular slope of the underlying ground          
   if ( damageValue > 0.8  ) {
       
       #this goes off every updateTime_s seconds approximately so the horizontal motion in one second is: (1.68780986 converts knots to ft per second)
       horizontalDistance_ft=speed_kt * knots2fps * updateTime_s;
       pitchangle2_deg = rad2degrees * math.atan2(damageAltAddCurrent_ft, horizontalDistance_ft );
       if (damageAltAddCurrent_ft ==0 and horizontalDistance_ft >0) pitchangle2_deg=0; #forward
       if (horizontalDistance_ft == 0 and damageAltAddCurrent_ft<0 ) pitchangle2_deg=-90; #straight down
       #Straight up won't happen here because we are (on purpose) forcing
       #the object down as we crash.  So we ignore the case.
       #if (horizontalDistance==0 and deltaAlt>0 ) pitchangle2=90; straight up
       
       #if no movement at all then we leave the pitch alone
       #if movement is less than 0.4 feet for pitch purposes we consider it
       #no movement at all--just a bit of wiggling
       noPitch=  ( (abs(damageAltAddCurrent_ft)< 0.5) and ( abs(horizontalDistance_ft) < 0.5));
       if (noPitch) pitchangle2_deg=0;   
       
       if (abs(pitchangle2_deg) > abs(pitchangle1_deg)) pitchangle_deg=pitchangle2_deg; 


       #vert-speed prob   
       if ( type != "aircraft" ) setprop (""~myNodeName~"/velocities/vertical-speed-fps",damageAltAddCurrent_ft * updateTime_s ); #since we do this updateTime_ss per second the vertical speed in FPS (ideally) exactly equals damageAltAddCurrent*updateTime_s

       #debprint ("speed-based pitchangle=", pitchangle2_deg, " hor=", horizontalDistance_ft, " dalt=", deltaAlt_ft);
     }



  #don't set pitch/roll for aircraft
  #debprint ("Bombable: setprop 4261");
  if (type != "aircraft" and thorough ) {
    #debprint ("Bombable: Setting roll-deg for ", myNodeName , " to ", rollangle_deg, " 1610");
    setprop (""~myNodeName~"/orientation/roll-deg", rollangle_deg );
    setprop (""~myNodeName~"/controls/flight/target-roll", rollangle_deg);
    #if (!noPitch) { #noPitch only applies to aircraft, not sure how it ever got here . . .
    # As of FG 2.4.0 FG doesn't let us change AI object pitch so all this code is a bit useless . . .     
      setprop (""~myNodeName~"/orientation/pitch-deg", pitchangle_deg );
      setprop (""~myNodeName~"/controls/flight/target-pitch", pitchangle_deg);
    #}
  
  }
  
  #if (crashing) debprint ("Crashing! damageAltAdd_deg and damageAltAddCurrent_deg, 
  #damageAltAddPrev & damageAltAddMax, damageAltMaxRate, damageAltMaxPerCycle ",
  #damageAltAdd_ft, " ",damageAltAddCurrent," ", damageAltAddPrev_ft, " ", 
  #damageAltAddMax_ft, " ", myNodeName, " ", damageAltMaxRate, " ", 
  #damageAltMaxPerCycle_ft, " ", updateTime_s );
                                                                      
  
  
  #setprop (""~myNodeName~"/velocities/vertical-speed-fps", verticalspeed);
   
  #set the target alt.  This mainly works for aircraft.         
  #when crashing, only do this if the new target alt is less then the current
  #target al
  #newTgtAlt_ft = targetAlt_ft + damageAltAddCurrent_ft;
  newTgtAlt_ft = targetAlt_ft;  
  currTgtAlt_ft = getprop (""~myNodeName~"/controls/flight/target-alt");#in ft
  if (currTgtAlt_ft==nil) currTgtAlt_ft=0;
  
  if ( (damageValue <= 0.8 ) or newTgtAlt_ft  < currTgtAlt_ft ) {
      #debprint ("Bombable: setprop 1625"); 
      setprop (""~myNodeName~"/controls/flight/target-alt", (newTgtAlt_ft ));   #target altitude--this is 10 feet or so in front of us for a ship or up to 1 minute in front for an aircraft
      #debprint ("1536 ", newTgtAlt_ft);
      #debprint ("1536 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
      #debprint ("Bombable: ", alt_ft, " ", toRightAlt_ft, " ",toLeftAlt_ft, " ",toFrontAlt_ft," ", toLeftAlt_ft, " ", alts.wheelsOnGroundAGL_ft);
  }
  
  #if going uphill base the altitude on the front of the vehicle (targetAlt).
  #This keeps the vehicle from sinking into the   
  #hillside when climbing.  This is a bit of a kludge that is simple/fast
  #because we have already calculated targetAlt in calculating the pitch.
  #To make this precise, calculate the correct position forward
  #based on the current speed of the current object and updateTime_s
  #and find the altitude of that spot.
  #For aircraft the targetAlt is the altitude 1 minute out IF that is higher
  #than the ground level.
  if (lookingAheadAlt_ft > alt_ft ) useAlt_ft = lookingAheadAlt_ft; else useAlt_ft=alt_ft;
  calcAlt_ft = (useAlt_ft + alts.wheelsOnGroundAGL_ft + alts.targetAGL_ft +  damageAltAddCumulative_ft + damageAltAddCurrent_ft);
  if (calcAlt_ft< objectsLowestAllowedAlt_ft) calcAlt_ft=objectsLowestAllowedAlt_ft;
   
   
  # calcAlt_ft=where the object should be, in feet                        
  #if it is an aircraft we try to control strictly via setting the target
  # altitude etc. (above).  If a ship etc. we just have to force it to that altitude (below).  However if an aircraft gets too close to the ground
  #the AI aircraft controls just won't react quickly enough so we "rescue"
  #it by simply moving it up a bit (see below).  
  #debprint ("type=", type);
  if (type != "aircraft") {
    #debprint ("Bombable: setprop 1652");
    setprop (""~myNodeName~"/position/altitude-ft", (calcAlt_ft) ); # feet
   }
   # for an aircraft, if it is within feet of the ground (and not forced 
   # there because of damage etc.) then we "rescue" it be putting it 25 feet 
   # above ground again.
   elsif (  currAlt_ft < toFrontAlt_ft + 75 and !(damageValue > 0.8 ) )   { 
         #debprint ("correcting!", myNodeName, " ", toFrontAlt_ft, " ", currAlt_ft, " ", currAlt_ft-toFrontAlt_ft, " ", toFrontAlt_ft+40, " ", currAlt_ft+20 );
         #set the pitch to try to make it look like we're climbing real
         #fast here, not just making an emergency correction . . .
         #for some reason the pitch is always aiming down when we
         #need to make a correction up, using pitchangle1. 
         #Kluge, we just always put pitch @30 degrees
         
         #vert-speed prob 
         setprop (""~myNodeName~"/orientation/pitch-deg", 30 );
         #debprint ("Bombable: setprop 1668");
         setprop (""~myNodeName~"/controls/flight/target-pitch", 30);
            
         if (currAlt_ft < toFrontAlt_ft + 25 ) { #dramatic correction
            debprint ("Bombable: Avoiding ground collision, "~ myNodeName);
            
            #addAltitude_ft is experimental/not quite working yet
            #addAltitude_ft (myNodeName, toFrontAlt_ft + 40-currAlt_ft, updateTime_s  );
            #debprint ("Bombable: setprop 1676");
            setprop (""~myNodeName~"/position/altitude-ft", toFrontAlt_ft + 40 );
            setprop (""~myNodeName~"/controls/flight/target-alt",  toFrontAlt_ft + 40);
            #debprint ("1749 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
            
            #vert-speed prob
            # 250 fps is achieved by a Zero in a normal barrel roll, so 300 fps is 
            # a pretty extreme/edge of reality maneuver for most aircraft
            # 
            # We are trying to set the vert spd to 300 fps but do it in
            # increments of 70 fps at most to try to maintain realism                        
            setVerticalSpeed (myNodeName, 300, 70, 8, .05);
        
            
           #debprint ("1557 vertspeed ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
             
          } else {   #more minor correction
            #debprint ("Correcting course to avoid ground, ", myNodeName);
            #setprop (""~myNodeName~"/position/altitude-ft", currAlt_ft + 20 );
            
            #addAltitude_ft is experimental/not quite working yet
            #addAltitude_ft (myNodeName, toFrontAlt_ft + 20 - currAlt_ft, updateTime_s  );
            #debprint ("Bombable: setprop 1691");            
            setprop (""~myNodeName~"/controls/flight/target-alt",  currAlt_ft + 20);
            #debprint ("1767 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
            
            #vert-speed prob
            # 250 fps is achieved by a Zero in a normal barrel roll, so 70 fps is
            # a very hard pull back on the stick in most aircraft, but not utterly 
            # impossible-looking.
            # 
            setVerticalSpeed (myNodeName, 70, 45, 4, .05);
             
          } 

   } 
   
   if ( type == "aircraft" and  (damageValue > 0.8 )) {
     #debprint ("Crashing! damageAltAdd & damageAltAddCurrent, damageAltAddPrev & damageAltAddMax, damageAltMaxRate, damageAltMaxPerCycle ",damageAltAdd, " ",damageAltAddCurrent," ", damageAltAddPrev, " ", damageAltAddMax, " ", myNodeName, " ", damageAltMaxRate, " ", damageAltMaxPerCycle, " ", updateTime_s );
     #if crashing we just force it to the right altitude, even if an aircraft
     #but we move it a maximum of damageAlMaxRate
     #if it's an airplane & it's crashing, we take it down as far as 
     #needed OR by the maximum allowed rate.
     
     #when it hits this altitude it is (or most very soon become)
     #completely kaput
     #For many objects, depending on how the model is set up, this 
     #may be somewhat higher or lower than actual ground level
     
     
     if ( damageAltMaxPerCycle_ft <  damageAltAddCurrent_ft )  {
         #setprop (""~myNodeName~"/position/altitude-ft", (objectsLowestAllowedAlt_ft + alts.wheelsOnGroundAGL_ft + damageAltAddCurrent) ); # feet
         #setprop (""~myNodeName~"/position/altitude-ft", (currAlt_ft + damageAltAddCurrent  - updateTime_s) ); # feet   
         #nice
         #debprint ("damageAltAddCurrent=", damageAltAddCurrent);
          #debprint ("Bombable: setprop 1720");
          setprop (""~myNodeName~"/controls/flight/target-alt",  currAlt_ft -500);
          #debprint ("1610 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
          setprop (""~myNodeName~"/controls/flight/target-pitch", -45);
          
          #vert-speed prob
          var orientPitch=getprop (""~myNodeName~"/orientation/pitch-deg");
          if ( orientPitch > -10) setprop (""~myNodeName~"/orientation/pitch-deg", orientPitch-1);
          
          
     } elsif (currAlt_ft + damageAltMaxPerCycle_ft  > objectsLowestAllowedAlt_ft ) { #put it down by the max allowed rate 
     
        #setprop (""~myNodeName~"/position/altitude-ft", (currAlt_ft + damageAltMaxPerCycle_ft ) );
          
        #setprop (""~myNodeName~"/position/altitude-ft", (currAlt_ft + damageAltAddCurrent_ft - updateTime_s*2 ) );
         #debprint ("damageAltAddCurrent=", damageAltAddCurrent);
         #not that nice
         #debprint ("Bombable: setprop 1737");
         setprop (""~myNodeName~"/controls/flight/target-alt",  currAlt_ft -10000);
         #debprint ("1625 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
         setprop (""~myNodeName~"/controls/flight/target-pitch", -70);
         
         var orientPitch_deg=getprop (""~myNodeName~"/orientation/pitch-deg");
        
        #vert-speed prob
        if (orientPitch_deg > -20) setprop (""~myNodeName~"/orientation/pitch-deg", orientPitch_deg - 1 );
          
         dodge (myNodeName); #it will roll/dodge as though under fire
        
         
     } else { #closer to the ground than MaxPerCycle so, just put it right on the ground.  Oh yeah, also explode etc.
     
        hitground_stop_explode(myNodeName, objectsLowestAllowedAlt_ft);
        debprint ("Bombable: Aircraft hit ground, it's dead. 1851.");
        
     
     }   
     #somehow the aircraft are getting below ground sometimes
     #sometimes it's just because they hit into a mountain or something
     #else in the way.
     #kludgy fix, just check for it & put them back on the surface 
     #if necessary.  And explode & stuff.
      
     aircraftAlt_ft = getprop (""~myNodeName~"/position/altitude-ft" );
     if ( aircraftAlt_ft < alt_ft - 5 )  {
           debprint ("Bombable: Aircraft hit ground, it's dead. 1863.");
           hitground_stop_explode(myNodeName, objectsLowestAllowedAlt_ft );
      }             
       
       
     
   } 
   
   #whatever else, we don't let objects go below their lowest allowed altitude
   #Maybe they are skidding along on teh ground, but they are not allowed
   # to skid along UNDER the ground . . .       
   if (currAlt_ft < objectsLowestAllowedAlt_ft)
      {
      #debprint ("Bombable: setprop 1775");
      setprop(""~myNodeName~"/position/altitude-ft", objectsLowestAllowedAlt_ft); #where the object is, in feet 
      }
   setprop(""~myNodeName~"/bombable/attributes/damageAltAddCurrent_ft", damageAltAddCurrent_ft);
   setprop(""~myNodeName~"/bombable/attributes/damageAltAddCumulative_ft", damageAltAddCumulative_ft + damageAltAddCurrent_ft);
   
  #debprint ("alt = ", alt, " currAlt_ft = ", currAlt_ft, " deltaAlt= ", deltaAlt, " altAdjust= ", alts.wheelsOnGroundAGL_ft, " calcAlt_ft=", calcAlt_ft, "damageAltAddCurrent=", damageAltAddCurrent, " ", myNodeName);
  
  
  
}



#######################################################
#location-check loop, a timer function, every 15-16 seconds to check if the object has been relocated (this will happen if the object is set up as an AI ship or aircraft and FG is reset).  If so it restores the object to its position before the reset.
#This solves an annoying problem in FG, where using file/reset (which
#you might do if you crash the aircraft, but also if you run out of ammo
#and need to re-load or for other reasons) will also reset the objects to 
#their original positions.
#With moving objects (set up as AI ships or aircraft with velocities, 
#rudders, and/or flight plans) the objects abre often just getting to 
#interesting/difficult positions, so we want to preserve those positions 
# rather than letting them reset back to where they started.
#TODO: Some of this could be done better using a listener on /sim/signals/reinit
var location_loop = func(id, myNodeName) {
  var loopid = getprop(""~myNodeName~"/bombable/loopids/location-loopid"); 
	id == loopid or return;

  #debprint ("location_loop starting");
  # reset the timer so we will check this again in 15 seconds +/-
  # add rand() so that all objects don't do this function simultaneously
  # when 15-20 objects are all doing this simultaneously it can lead to jerkiness in FG 
  settimer(func {location_loop(id, myNodeName); }, 15 + rand() );
	
	#get out of here if Bombable is disabled
  if (! getprop(bomb_menu_pp~"bombable-enabled") ) return;
	
	var node = props.globals.getNode(myNodeName);
	
	
	var started = getprop (""~myNodeName~"/position/previous/initialized");
	
  var lat = getprop(""~myNodeName~"/position/latitude-deg");
  var lon = getprop(""~myNodeName~"/position/longitude-deg");
  var alt_ft = getprop(""~myNodeName~"/position/altitude-ft");
  
  if (lat==nil) {
        lat=0; 
        debprint ("Bombable: Lat=NIL, location_loop", myNodeName);
  }
  if (lon==nil) {
        lon=0; 
        debprint ("Bombable: Lon=NIL, location_loop", myNodeName);
  }


  
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
     var prevalt_ft = getprop(""~myNodeName~"/position/previous/altitude-ft");
     var prev_global_x = getprop(""~myNodeName~"/position/previous/global-x");
     var prev_global_y = getprop(""~myNodeName~"/position/previous/global-y");
     var prev_global_z = getprop(""~myNodeName~"/position/previous/global-z");
 
     
     var prev_distance = getprop(""~myNodeName~"/position/previous/distance");
     
     var GeoCoord = geo.Coord.new();
     GeoCoord.set_latlon(lat, lon, alt_ft * feet2meters);

     var GeoCoordprev = geo.Coord.new();
     GeoCoordprev.set_latlon(prevlat, prevlon, prevalt_ft * feet2meters);

     var directDistance = GeoCoord.distance_to(GeoCoordprev);
     
     #debprint ("Object  ", myNodeName ", distance: ", directDistance);
     
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
       node.getNode("position/altitude-ft", 1).setDoubleValue(prevalt_ft);
       #now we want to show the previous location as this newly relocated position and distance traveled = 0;
       lat=prevlat;
       lon=prevlon;
       alt_ft=prevalt_ft;
       
 
       debprint ("Bombable: Repositioned object "~ myNodeName~ " to lat: "~ prevlat~ " long: "~ prevlon~ " altitude: "~ prevalt_ft~" ft.");
     }
  }  
  #now we save the current position 
  node.getNode("position/previous/initialized", 1).setBoolValue(1);
  node.getNode("position/previous/latitude-deg", 1).setDoubleValue(lat);
  node.getNode("position/previous/longitude-deg", 1).setDoubleValue(lon);
  node.getNode("position/previous/altitude-ft", 1).setDoubleValue(alt_ft);
  node.getNode("position/previous/global-x", 1).setDoubleValue(global_x);
  node.getNode("position/previous/global-y", 1).setDoubleValue(global_y);
  node.getNode("position/previous/global-z", 1).setDoubleValue(global_z);   
 
  node.getNode("position/previous/distance", 1).setDoubleValue(directDistance);

}
#################################################################
# This is the old way of calculating the closest impact distance 
# This approach uses more of the geo.Coord functions from geo.nas
# The other approach is more vector based and uses a local XYZ
# coordinate system based on lat/lon/altitude.
# I'm not sure which is the most accurate but I believe this one is slower,
# with multiple geo.Coord calls plus some trig. 
var altClosestApproachCalc = func {

 	# figure how close the impact and terrain it's on
	var objectGeoCoord = geo.Coord.new();
	objectGeoCoord.set_latlon(oLat_deg,oLon_deg,oAlt_m );
	var impactGeoCoord = geo.Coord.new();
	impactGeoCoord.set_latlon(iLat_deg, iLon_deg, iAlt_m);
	
	#impact point as though at the same altitude as the object - for figuring impact distance on the XY plane
	var impactSameAltGeoCoord = geo.Coord.new();
	impactSameAltGeoCoord.set_latlon(iLat_deg, iLon_deg, oAlt_m);


  var impactDistanceXY_m = objectGeoCoord.direct_distance_to(impactSameAltGeoCoord);	

	if (impactDistanceXY_m >200 ) {
      #debprint ("Not close in surface distance. ", impactDistanceXY_m);
      #return; 
  }
  
    var impactDistance_m = objectGeoCoord.direct_distance_to(impactGeoCoord);   

  #debprint ("impactDistance ", impactDistance_m);
    
  var impactHeadingDelta_deg=math.abs ( impactGeoCoord.course_to(objectGeoCoord) -  impactorHeading_deg );
  
  
 

  #the pitch angle from the impactor to the main object 
  var impact2ObjectPitch_deg = rad2degrees * math.asin ( deltaAlt_m/impactDistance_m);
         
  var impactPitchDelta_deg = impactorPitch_deg - impact2ObjectPitch_deg;
         
  #Closest approach of the impactor to the center of the object along the direction of pitch       
  var closestApproachPitch_m = impactDistance_m * math.sin (impactPitchDelta_deg /rad2degrees);   

  # This formula calcs the closest distance the object would have passed from the exact center of the target object, where 0 = a direct hit through the center of the object; on the XY plane     
  var closestApproachXY_m = math.sin (impactHeadingDelta_deg/rad2degrees) * impactDistanceXY_m * math.cos (impactPitchDelta_deg /rad2degrees);; 

           
  #combine closest approach in XY and closest approach along the pitch angle to get the
  # overall point of closest approach  
  var closestApproachOLDWAY_m = math.sqrt ( 
      closestApproachXY_m * closestApproachXY_m +
      closestApproachPitch_m * closestApproachPitch_m);         
  
  #debprint ("Bombable: Projected closest impact distance : ", closestApproachOLDWAY_m, "FG Impact Detection Point: ", impactDistance_m, " XY: ", closestApproachXY_m, " Pitch: ", closestApproachPitch_m, " impactDistance_m=",impactDistance_m, " impactDistanceXY_m=",impactDistanceXY_m, " ballisticMass_lb=", ballisticMass_lb);
    
  if (impactDistance_m<closestApproach_m) debprint ("#########CLOSEST APPROACH CALC ERROR########");          

}  

########################################
# put_splash puts the impact splash from test_impact
# 
var put_splash = func (nodeName, iLat_deg,iLon_deg, iAlt_m, ballisticMass_lb, impactTerrain="terrain", refinedSplash=0, myNodeName="" ){

 
 #This check to avoid duplicate splashes is not quite working in some cases
 # perhaps because the lat is repeating exactly for different impacts, or
 # because some weapon impacts and collisions are reported a little differently?   
 var impactSplashPlaced = getprop (""~nodeName~"/impact/bombable-impact-splash-placed");
 var impactObjectLat_deg= getprop (""~nodeName~"/impact/latitude-deg");
 
 if ((impactSplashPlaced==nil or impactSplashPlaced!=impactObjectLat_deg) and iLat_deg!=nil and iLon_deg!=nil and iAlt_m!=nil){

       
       
       records.record_impact ( myNodeName: myNodeName, damageRise:0, damageIncrease:0, damageValue:0, impactNodeName: nodeName, ballisticMass_lb: ballisticMass_lb, lat_deg: iLat_deg, lon_deg: iLon_deg, alt_m: iAlt_m );

       if (ballisticMass_lb<1.2) { 
         var startSize_m=0.25 + ballisticMass_lb/3;
         var endSize_m= 1 + ballisticMass_lb;
       } else {
         var startSize_m=0.25 + ballisticMass_lb/1000;
         var endSize_m= 2 + ballisticMass_lb/4; 
       }                                               
       
       impLength_sec=0.75+ ballisticMass_lb/1.2;
       if (impLength_sec>20) impLength_sec=20;
       
       #The idea is that if the impact hits earth it throws up a bunch of 
       #dirt & dust & stuff for a longer time.  But only for smaller/projectile
       #weapons where the dirt/dust is the main visual.  
       # Based on observing actual weapons impacts on Youtube etc.
       # 
       if (impactTerrain=="terrain" and ballisticMass_lb<=1.2) {
         endSize_m *= 5;
         impLength_sec *= 5;
       }

      #debprint ("Bombable: Drawing impact, ", nodeName, " ", iLat_deg, " ", iLon_deg, " ",  iAlt_m, " refined:", refinedSplash );
      put_remove_model(iLat_deg,iLon_deg, iAlt_m, impLength_sec, startSize_m, endSize_m);
      #for larger explosives (or a slight chance with smaller rounds, which
      # all have some incindiary content) start a fire
      if (ballisticMass_lb>1.2 or 
         (ballisticMass_lb <=1.2 and rand()<ballisticMass_lb/10) ) settimer ( func {start_terrain_fire( iLat_deg,iLon_deg,iAlt_m, ballisticMass_lb )}, impLength_sec/1.5);
      setprop (""~nodeName~"/impact/bombable-impact-splash-placed", impactObjectLat_deg);                          
 }
 
      if  (refinedSplash)
          setprop (""~nodeName~"/impact/bombable-impact-refined-splash-placed", impactObjectLat_deg);  


}


########################################
# exit_test_impact(nodeName)
# draws the impact splash for the nodeName
# 
var exit_test_impact= func(nodeName, myNodeName){


 #if impact on a ship etc we're assuming that one of the other test_impact
 # instances will pick it up & we don't need to worry about it. 
 var impactTerrain = getprop(""~nodeName~"/impact/type");
 if (impactTerrain!="terrain") {
    #debprint ("Bombable: Not drawing impact; object impact");
    return;
 }
 
 var iLat_deg=getprop(""~nodeName~"/impact/latitude-deg");
 var iLon_deg=getprop(""~nodeName~"/impact/longitude-deg");
 var iAlt_m=getprop(""~nodeName~"/impact/elevation-m");
 
 
 var ballisticMass_lb= getBallisticMass_lb(nodeName); 

 #debprint ("Bombable: Exiting test_impact with a splash, ", nodeName, " ", ballisticMass_lb, " ", impactTerrain," ", iLat_deg, " ", iLon_deg, " ", iAlt_m);
 
  put_splash (nodeName, iLat_deg, iLon_deg, iAlt_m, ballisticMass_lb, impactTerrain, 0, myNodeName );


}

var getBallisticMass_lb = func (impactNodeName) {

#weight/mass of the ballistic object, in lbs    	
  #var ballisticMass_lb = impactNode.getNode("mass-slug").getValue() * 32.174049; 
    
  var ballisticMass_lb=0;
  var ballisticMass_slug = getprop (""~impactNodeName~"/mass-slug");

  #ok, FG 2.4.0 leaves out the /mass-slug property, so we have to improvise.
  # We basically need to list or guess the mass of each & every type of ordinance
  # that might exist or be used.  Not good. 
  if (ballisticMass_slug != nil ) ballisticMass_lb = ballisticMass_slug *  32.174049
  else {
     ballisticMass_lb=.25;
     var impactType = getprop (""~impactNodeName~"/name");
     #debprint ("Bombable: ImpactNodeType = ", impactType);
     if (impactType==nil) impactType="bullet";

     
     
     #we start with specific & end with generic, so the specific info will take
     # precedence (if we have it)     
     if (find ("MK-81", impactType ) != -1 ) ballisticMass_lb=250;
     elsif (find ("MK-82", impactType ) != -1 ) ballisticMass_lb=500;
     elsif (find ("MK82", impactType ) != -1 ) ballisticMass_lb=500;     
     elsif (find ("MK-83", impactType ) != -1 ) ballisticMass_lb=1000;
     elsif (find ("MK-84", impactType ) != -1 ) ballisticMass_lb=2000;
     elsif (find ("25 pound", impactType ) != -1 ) ballisticMass_lb=25;
     elsif (find ("5 pound", impactType ) != -1 ) ballisticMass_lb=5;
     elsif (find ("100 pound", impactType ) != -1 ) ballisticMass_lb=100;
     elsif (find ("150 pound", impactType ) != -1 ) ballisticMass_lb=150;          
     elsif (find ("250 pound", impactType ) != -1 ) ballisticMass_lb=250;
     elsif (find ("500 pound", impactType ) != -1 ) ballisticMass_lb=500;
     elsif (find ("1000 pound", impactType ) != -1 ) ballisticMass_lb=1000;
     elsif (find ("2000 pound", impactType ) != -1 ) ballisticMass_lb=2000;
     elsif (find ("aim-9", impactType ) != -1 ) ballisticMass_lb=20.8;
     elsif (find ("AIM", impactType ) != -1 ) ballisticMass_lb=20.8;
     elsif (find ("WP-1", impactType ) != -1 ) ballisticMass_lb=23.9;
     elsif (find ("GAU-8", impactType ) != -1 ) ballisticMass_lb=0.9369635;
     elsif (find ("M-61", impactType ) != -1 ) ballisticMass_lb=0.2249;
     elsif (find ("M61", impactType ) != -1 ) ballisticMass_lb=0.2249;
     elsif (find ("LAU", impactType ) != -1 ) ballisticMass_lb=86; #http://www.dtic.mil/dticasd/sbir/sbir041/srch/af276.pdf
     elsif (find ("smoke", impactType ) != -1 ) ballisticMass_lb=0.0;
     elsif (find (".50 BMG", impactType ) != -1 ) ballisticMass_lb=0.130072735;
     elsif (find (".50", impactType ) != -1 ) ballisticMass_lb=0.130072735;     
     elsif (find ("303", impactType ) != -1 ) ballisticMass_lb=0.0264554715; #http://en.wikipedia.org/wiki/Vickers_machine_gun
     elsif (find ("gun", impactType ) != -1 ) ballisticMass_lb=.025;
     elsif (find ("bullet", impactType) != -1 ) ballisticMass_lb=0.0249122356;
     elsif (find ("tracer", impactType) != -1 ) ballisticMass_lb=0.0249122356;
     elsif (find ("round", impactType) != -1 ) ballisticMass_lb=0.9369635;
     elsif (find ("cannon", impactType ) != -1 ) ballisticMass_lb=0.282191696;
     elsif (find ("bomb", impactType ) != -1 ) ballisticMass_lb=250;
     elsif (find ("heavy-bomb", impactType ) != -1 ) ballisticMass_lb=750;
     elsif (find ("rocket", impactType ) != -1 ) ballisticMass_lb=50;
     elsif (find ("missile", impactType ) != -1 ) ballisticMass_lb=185;     
     
  }

  return ballisticMass_lb;
}

var getImpactVelocity_mps = func (impactNodeName=nil,ballisticMass_lb=.25) {

  var impactVelocity_mps = getprop (""~impactNodeName~"/impact/speed-mps");
  
  #if perchance impact velocity isn't available we'll estimate it from
  # projectile size  
  # These are rough approximations/guesses based on http://en.wikipedia.org/wiki/Muzzle_velocity  
  if (impactVelocity_mps == nil or impactVelocity_mps== 0) {
    if (ballisticMass_lb < 0.1) impactVelocity_mps= 1200;
    elsif (ballisticMass_lb < 0.5) impactVelocity_mps= 900;
    elsif (ballisticMass_lb < 2) impactVelocity_mps= 500;
    elsif (ballisticMass_lb < 50) impactVelocity_mps= 250;
    elsif (ballisticMass_lb < 500) impactVelocity_mps= 150;
    elsif (ballisticMass_lb < 2000) impactVelocity_mps= 125;
    else impactVelocity_mps= 100;
  }  
  return impactVelocity_mps;
}

########################################
# cartesianDistance (x,y,z, . . . )
# returns the cartesian distance of any number of elements
var cartesianDistance = func  (elem...){
 var dist=0;
 foreach (e; elem ) dist+=e*e;
 return math.sqrt(dist);
} 

################################################
#FUNCTION test_impact
#
#listener function on ballistic impacts
#checks if the impact has hit our object and if so, adds the damage
# damageMult can be set high (for easy to damage things) or low (for
# hard to damage things).  Default/normal value (M1 tank) should be 1.  

# FG uses a very basic collision detection algorithm that assumes a standard
# height and length for each type of AI object.  These are actually 'radius'
# type measurements--ie for the 2nd object, if the ballistic obj strikes 50 ft
#above OR 50 ft below, and within a circle of radius 100 ft of the lat/lon,
#then we get a hit.  From the C code:
# // we specify tgt extent (ft) according to the AIObject type
#    double tgt_ht[]     = {0,  50, 100, 250, 0, 100, 0, 0,  50,  50, 20, 100,  50};	
#    double tgt_length[] = {0, 100, 200, 750, 0,  50, 0, 0, 200, 100, 40, 200, 100};
# http://gitorious.org/fg/flightgear/blobs/next/src/AIModel/AIManager.cxx

# In order, those are:
# enum object_type { otNull = 0, otAircraft, otShip, otCarrier, otBallistic,
#  otRocket, otStorm, otThermal, otStatic, otWingman, otGroundVehicle,
#  otEscort, otMultiplayer,
#  MAX_OBJECTS };
# http://gitorious.org/fg/flightgear/blobs/next/src/AIModel/AIBase.hxx

#So Aircraft is assumed to be 50 feet high, 100 ft long; multiplayer the same, etc.
#That is where any ballistic objects are detected and stopped by FG.
# 
# A main point of the function below is to improve on this impact detection
# by projecting the point of closest approach of the impactor, then assigning
# a damage value based on that.
# 


  
var test_impact = func(changedNode, myNodeName) {

   	#Allow this function to be disabled via bombable menu
    if ( ! getprop(bomb_menu_pp~"bombable-enabled") ) return;

  var impactNodeName = changedNode.getValue();
	#var impactNode = props.globals.getNode(impactNodeName);
	
	
	#debprint ("Bombable: test_impact, ", myNodeName," ", impactNodeName);

	var oLat_deg=getprop (""~myNodeName~"/position/latitude-deg");
	var iLat_deg=getprop (""~impactNodeName~"/impact/latitude-deg");


   # bhugh, 3/28/2013, not sure why this error is happening sometimes in 2.10:
   # Nasal runtime error: No such member: maxLat
   #  at E:/FlightGear 2.10.0/FlightGear/data/Nasal/bombable.nas, line 3405
   #  called from: E:/FlightGear 2.10.0/FlightGear/data/Nasal/bombable.nas, line 8350
   #  called from: E:/FlightGear 2.10.0/FlightGear/data/Nasal/globals.nas, line 100
	
	var maxLat_deg = attributes[myNodeName].dimensions.maxLat;
	var maxLon_deg = attributes[myNodeName].dimensions.maxLon;
	
	attributes[myNodeName].dimensions.maxLon;
	
	                                  
  #quick-n-dirty way to tell if an impact is close to our object at all
  #without processor-intensive calculations
  #we do this first and then exit if not close, to reduce impact
  #of impacts on processing time
  # 
  #       
	var deltaLat_deg=(oLat_deg-iLat_deg);
	if (abs(deltaLat_deg) > maxLat_deg * 1.5 ) {
      #debprint ("Not close in lat. ", deltaLat_deg);
      exit_test_impact(impactNodeName, myNodeName);
      return; 
  }    
	
  var oLon_deg= getprop (""~myNodeName~"/position/longitude-deg");
  var iLon_deg= getprop (""~impactNodeName~"/impact/longitude-deg");

  var deltaLon_deg=(oLon_deg-iLon_deg);
	if (abs(deltaLon_deg) > maxLon_deg * 1.5 )  {
      #debprint ("Not close in lon. ", deltaLon_deg);
      exit_test_impact(impactNodeName, myNodeName);
      return; 
  }

  var oAlt_m= getprop (""~myNodeName~"/position/altitude-ft")*feet2meters;
  var iAlt_m= getprop (""~impactNodeName~"/impact/elevation-m");
  var deltaAlt_m = (oAlt_m-iAlt_m);
	
	if (abs(deltaAlt_m) > 300 ) {
      #debprint ("Not close in Alt. ", deltaAlt);
      exit_test_impact(impactNodeName, myNodeName);      
      return; 
  }
	
  #debprint ("Impactor: ", impactNodeName, ", Object: ", myNodeName);
	if (impactNodeName=="" or impactNodeName==nil) {
      #debprint ("impactNode doesn't seem to exist, exiting");
      return; 
  }

  #Since FG kindly intercepts collisions along a fairly large target cylinder surrounding the 
  # object, we simply project the last known heading of the ballistic object along
  # its path to determine how close to the center of the object it would have struck,
  # if it continued along its present heading in a straight line.       

  # we do this for both terrain & ship/aircraft hits, because if the aircraft or ship is on 
  # or very close to the ground, FG often lets the ai submodel go 'right through' the main
  # object and the only impact detected is with the ground.  This gets worse as the framerate
  # gets slow, because FG can only check for impacts at each frame - so with a projectile
  # going 1000 MPS and framerate of 10, that is only once every hundred meters. 
  
  # Formula here:      
  # http://mathforum.org/library/drmath/view/54731.html (a more vector-based
  # approach).
  # 	
  # ft_per_deg_lat = 366468.96 - 3717.12 * cos(pos.getLatitudeRad());
  # ft_per_deg_lon = 365228.16 * cos(pos.getLatitudeRad());
  # per FG c code, http://gitorious.org/fg/flightgear/blobs/next/src/AIModel/AIBase.cxx line 178 
  # We could speed this up by leaving out the cos term in deg_lat and/or calculating these
  # occasionally as the main A/C flies around and storing them (they dont change that)
  # much from one mile to the next)       
  #var iLat_rad=iLat_deg/rad2degrees;  
  #m_per_deg_lat= 111699.7 - 1132.978 * math.cos (iLat_rad);
  #m_per_deg_lon= 111321.5 * math.cos (iLat_rad);
  
  #m_per_deg_lat=getprop ("/bombable/sharedconstants/m_per_deg_lat");
  #m_per_deg_lon=getprop ("/bombable/sharedconstants/m_per_deg_lon");
  
  #the following plus deltaAlt_m make a <vector> where impactor is at <0,0,0>
  # and target object is at <deltaX,deltaY,deltaAlt> in relation to it.  
  var deltaY_m=deltaLat_deg*m_per_deg_lat;
  var deltaX_m=deltaLon_deg*m_per_deg_lon;
  
  #calculate point & distance of closest approach.
  # if the main aircraft (myNodeName=="") then we just 
  # use FG's impact detection point.  If an AI or MP
  # aircraft, we project it into actual point of closest approach.        
  if (myNodeName=="") {

    closestApproach_m= cartesianDistance(deltaX_m,deltaY_m,deltaAlt_m );
  
  } else {
  
    #debprint ("MPDL:", m_per_deg_lat, " MPDLon: ", m_per_deg_lon, " dL:", deltaLat_deg, " dLon:", deltaLon_deg);
    
    impactorHeading_deg = getprop (""~impactNodeName~"/impact/heading-deg");
    #if perchance this doesn't exist we'll just randomize it; it must be -90 to 90 or it wouldn't have hit.
    if (impactorHeading_deg==nil ) impactorHeading_deg=rand() * 180 - 90;
  
    impactorPitch_deg = getprop (""~impactNodeName~"/impact/pitch-deg");
    #if perchance this doesn't exist we'll just randomize it; it must be -90 to 90 or it wouldn't have hit.
    if (impactorPitch_deg==nil ) impactorPitch_deg=rand() * 180 - 90;
  
  
    # the following make a unit vector in the direction the impactor is moving
    # this could all be saved in the prop tree so as to avoid re-calcing in 
    # case of repeated AI objects checking the same impactor    
    var impactorPitch_rad=impactorPitch_deg/rad2degrees;  
    var impactorHeading_rad=impactorHeading_deg/rad2degrees;
    var impactordirectionZcos=math.cos(impactorPitch_rad);  
    var impactorDirectionX=math.sin(impactorHeading_rad) * impactordirectionZcos; #heading
    var impactorDirectionY=math.cos(impactorHeading_rad) * impactordirectionZcos; #heading
    var impactorDirectionZ=math.sin(impactorPitch_rad); #pitch
          
    #now we have a simple vector algebra problem: the impactor is at <0,0,0> moving
    # in the direction of the <impactorDirection> vector and the object is
    # at point <deltaX,deltaY,deltaAlt>.
    # So the closest approach of the line through <0,0,0> in the direction of <impactorDirection>
    # to point <deltaX,deltaY,deltaAlt> is the length of the cross product  vector 
    # <impactorDirection> X <deltaX,deltaY,deltaAlt> divided by the length of
    #  <impactorDirection>.  We have cleverly chosen <impactDirection> so as to always
    # have length one (unit vector), so we can skip that calculation.   
    # So the cross product vector:
    
    var crossProdX_m=impactorDirectionY*deltaAlt_m - impactorDirectionZ*deltaY_m;
    var crossProdY_m=impactorDirectionZ*deltaX_m   - impactorDirectionX*deltaAlt_m;
    var crossProdZ_m=impactorDirectionX*deltaY_m   - impactorDirectionY*deltaX_m;  
    
    #the length of the cross-product vector divided by the length of the line/direction
    # vector is the distance we want (and the line/direction vector = 1 in our 
    # setup:  
    closestApproach_m= cartesianDistance(crossProdX_m,crossProdY_m,crossProdZ_m );
        
         
    #debprint( "closestApproach_m=", closestApproach_m, " impactorDirectionX=", impactorDirectionX,
    #" impactorDirectionY=", impactorDirectionY,
    #" impactorDirectionZ=", impactorDirectionZ,
    #" crossProdX_m=", crossProdX_m,
    #" crossProdY_m=", crossProdY_m,
    #" crossProdZ_m=", crossProdZ_m,
    #" deltaX_m=", deltaX_m,
    #" deltaY_m=", deltaY_m,
    #" deltaAlt_m=", deltaAlt_m,
    #" impactDist (lat/long) ", cartesianDistance(deltaX_m,deltaY_m,deltaAlt_m), 
    #" shouldbeOne: ", cartesianDistance(impactorDirectionX,impactorDirectionY,impactorDirectionZ),
    #);                     
  
    #var impactSurfaceDistance_m = objectGeoCoord.distance_to(impactGeoCoord);
  	#var heightDifference_m=math.abs(getprop (""~impactNodeName~"/impact/elevation-m") - getprop (""~nodeName~"/impact/altitude-ft")*feet2meters);
  }

  var damAdd=0; #total amoung of damage actually added as the result of the impact
  var impactTerrain = getprop (""~impactNodeName~"/impact/type");
   
  #debprint ("Bombable: Possible hit - calculating . . . ", impactTerrain);

    #Potential for adding serious damage increases the closer we are to the center
  #of the object.  We'll say more than damageRadius meters away, no potential for increased damage 
  
  var damageRadius_m = attributes[myNodeName].dimensions.damageRadius_m;
  var vitalDamageRadius_m = attributes[myNodeName].dimensions.vitalDamageRadius_m;
  # if it doesn't exist we assume it is 1/3 the damage radius
  if (!vitalDamageRadius_m) vitalDamageRadius_m = damageRadius_m/3; 
  
  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  var vuls= attributes[myNodeName].vulnerabilities;
   
  ballisticMass_lb= getBallisticMass_lb(impactNodeName);
  var ballisticMass_kg=ballisticMass_lb/2.2;
    
  #Only worry about small arms/small cannon fire if it is a direct hit on the object;
  # if it hits terrain, then no damage.  
  if (impactTerrain == "terrain" and ballisticMass_lb<=1.2) { 
   #debprint ("hit on terrain & mass < 1.2 lbs, exiting ");
   exit_test_impact(impactNodeName, myNodeName);   
   return;
  } 

  var impactVelocity_mps = getImpactVelocity_mps (impactNodeName, ballisticMass_lb);  

  #How many shots does it take to down an object?  Supposedly the Red Baron
  #at times put in as many as 500 machine-gun rounds into a target to *make
  #sure* it really went down.
  
  var easyMode=1;
  var easyModeProbability=1;
  
  if (myNodeName!="" ) {
      #Easy Mode increases the damage radius (2X), making it easier to score hits, 
      #but doesn't increase the damage done by armament
      if (getprop(""~bomb_menu_pp~"easy-mode")) {
         #easyMode*=2;
         damageRadius_m*=2;
         vitalDamageRadius_m*=2;
      }
         
      #Super Easy mode increases both the damage radius AND the damage done  
      #by 3X 
      if (getprop(""~bomb_menu_pp~"super-easy-mode")){
          easyMode*=3;
          easyModeProbability*=3;        
          damageRadius_m*=3;
          vitalDamageRadius_m*=3;
       }
  }   

  # debprint ("Bombable: Projected closest impact distance delta : ", closestApproachOLDWAY_m-closestApproach_m, "FG Impact Detection Point delta: ", impactDistance_m - cartesianDistance(deltaX_m,deltaY_m,deltaAlt_m), " ballisticMass_lb=", ballisticMass_lb);

  #var tgt_ht_m=50/.3042 + 5; # AIManager.cxx it is 50 ft for aircraft & multiplayer;extra 5 m is fudge factor
  #var tgt_length_m=100/.3024 + 5; # AIManager.cxx it is 100 ft for aircraft & multiplayer; extra 5 m is fudge factor  
    
  #if impactterrain is aircraft or MP and the impact is within the tgt_alt and tgt_height, we're going to assume it is a direct impact on this object.
  # it would be much easier if FG would just pass us the node name of the object that has been hit,
  # but lacking that vital bit of info, we do it the hard way . . .    
	#if(abs(iAlt_m-oAlt_m) < tgt_ht_m   and impactDistanceXY_m < tgt_length_m   and impactTerrain != "terrain") {  

  #OK, it's within the damage radius - direct hit
  if (closestApproach_m < damageRadius_m) {
            
      
      damagePotential=0;
      outsideIDdamagePotential=0;
      #Kinetic energy ranges from about 1500 joules (Vickers machine gun round) to
      # 200,000 joules (GAU-8 gatling gun round .8 lbs at 1000 MPS typical impact speed)
      # to 220,000 joules (GAU-8 at muzzle velocity)
      # to 330,000 joules (1.2 lb projectile at 1500 MPS muzzle velocity)
      # GAU-8 can penetrate an M-1 tank at impact.  But even there it would take a number of rounds,
      # perhaps a large number, to disable a tank reliably.  So let's say 20 rounds, and 
      # our 100% damage amount is 20 GAU hits.            
      #                               
      # Kinetic Energy (joules) = 1/2* mass * velocity^2  (mass in kg, velocity in mps)
      # See http://en.wikipedia.org/wiki/Kinetic_energy   
      #var kineticEnergy_joules= ballisticMass_kg *  impactVelocity_mps * impactVelocity_mps /2; 
    
      #According to this, weapon effectiveness isn't well correlated to kinetic energy, but
      # is better estimated in proportion to momentum
      # plus a factor for the chemical explosiveness of the round:
      #             http://eaw.wikispaces.com/Technical+Tools--Gun+Power
      # 
      # We don't have a good way to estimate the chemical energy of particular rounds 
      # (though it can be looked up) but momentum is easy: mass X velocity.
      # 
      # Momentum ranges from 500 kg * m/s for a typical Vickers machine gun round
      # to 180 for a GAU-8 round at impact, 360 for  GAU-8 round at muzzle, 800 for
      # at 1.2 lb slug at 1500 mps                        
      # 
      momentum_kgmps = ballisticMass_kg *  impactVelocity_mps;
       
      weaponDamageCapability=momentum_kgmps/(60*360); 
      #debprint ("mass= ", ballisticMass_lb, " vel=", impactVelocity_mps, " Ek=", kineticEnergy_joules, " damageCapability=", weaponDamageCapability);
                  
      
      
      #likelihood of damage goes up the closer we are to the center; it becomes 1 at vitalDamageRadius
                          
      if (closestApproach_m <= vitalDamageRadius_m )impactLikelihood=1;
      else impactLikelihood=(damageRadius_m - closestApproach_m)/(damageRadius_m -vitalDamageRadius_m);
      
      
      
      #It's within vitalDamageRadius, this is the core of the object--engines pilot, fuel tanks, 
      # etc.  #So, some chance of doing high damage and near certainty of doing some damage
      if (closestApproach_m <= vitalDamageRadius_m )  { 
           #damagePotential = (damageRadius_m - closestApproach_m)/damageRadius_m;
           damagePotential = impactLikelihood * vuls.damageVulnerability / 200; #possibility of causing a high amount of damage           
           outsideIDdamagePotential=impactLikelihood; #possibility of causing a routine amount of damage
           
#          debprint ("Bombable: Direct hit, "~ impactNodeName~ " on ", myNodeName, " Distance= ", closestApproach_m, " heightDiff= ", deltaAlt_m, " terrain=", impactTerrain, " radius=", damageRadius_m, " dP:", damagePotential, " oIdP:", outsideIDdamagePotential, " bM:", ballisticMass_lb);
        
        
      } else {
           #It's within damage radius but not vital damage Radius: VERY slim chance 
           # of doing serious damage, like hitting a wing fuel tank or destroying a wing strut, and
           #some chance of doing routine damage
                     
           damagePotential= impactLikelihood * vuls.damageVulnerability / 2000;
           
           #Think of a typical aircraft projected onto the 2D plane with damage radius &
           # vital damage radius superimposed over them.  For vital damage radius, it's right near 
           # the center and  most of the area enclosed would be a hit.  
           # But for the area between vital damage radius & damage
           # radius, there is much empty space--and the more so, the more outwards we go 
           # towards the damage radius.  Squaring the oIdP takes this geometrical fact into 
           # account--there is more and more area the further you go out, but more and more of
           # it is empty.  So there is less chance (approximately proportionate to 
           # square of distance from center) of hitting something vital the further 
           # you go out.                                                          
           #                         
           outsideIDdamagePotential= math.pow (impactLikelihood, 1.5) ;# ^2 makes it a bit too difficult to get a hit/let's try ^1.5 instead 
           
#           debprint ("Bombable: Near hit, "~ impactNodeName~ " on ", myNodeName, " Distance= ", closestApproach_m, " heightDiff= ", deltaAlt_m, " terrain=", impactTerrain, " radius=", damageRadius_m, " dP ", damagePotential, " OIdP ", outsideIDdamagePotential, " vitalHitchance% ", damagePotential*vuls.damageVulnerability*easyModeProbability * ballisticMass_lb / 5);
           
      }         
        
  
    
                    
    var damageCaused=0;    
		if (ballisticMass_lb < 1.2) {
    # gun/small ammo
    
        
      #Guarantee of some damage, maybe big damage if it hits some vital parts
      # (the 'if' is a model for the percentage chance of it hitting some vital part, 
      #  which should happen only occasionally--and less occasionally for well-armored targets)
      # it always does at least 100% of weaponDamageCapability and up to 300%             
      if ( rand()< damagePotential*easyModeProbability) {
         damageCaused=(weaponDamageCapability + rand()*weaponDamageCapability*2)*vuls.damageVulnerability*easyMode;  
         #debprint ("Bombable: Direct Hit/Vital hit. ballisticMass: ", ballisticMass_lb," damPotent: ", damagePotential, " weaponDamageCapab:", weaponDamageCapability);

          debprint ("Bombable: Small weapons, direct hit, very damaging");           
       	
      #Otherwise the possibility of damage 	
  		} elsif (rand() < outsideIDdamagePotential) {
  		 
           damageCaused=rand () * weaponDamageCapability * vuls.damageVulnerability*easyMode * outsideIDdamagePotential;      
           #debprint ("Bombable: Direct Hit/Nonvital hit. ballisticMass: ", ballisticMass_lb," outsideIDDamPotent: ", outsideIDdamagePotential, " weaponDamageCapab:", weaponDamageCapability  );

           debprint ("Bombable: Small weapons, direct hit, damaging");
  
      }  			
 
			
		} else {
		# anything larger than 1.2 lbs making a direct hit.  It's some kind of bomb or 
		# exploding ordinance, presumably	
		  #debprint ("larger than 1.2 lbs, making direct hit");    	
		 
		  var damagePoss= .6 + ballisticMass_lb/250;

		  if (damagePoss>1) damagePoss=1;
			# if it hits a vital spot (which becomes more likely, the larger the bomb)
     	if ( rand()< damagePotential*vuls.damageVulnerability*easyModeProbability * ballisticMass_lb / 5  ) damageCaused=damagePoss*vuls.damageVulnerability*ballisticMass_lb*easyMode/2; 
		  else  #if it hits a regular or less vital spot
         damageCaused=rand () * ballisticMass_lb * vuls.damageVulnerability*easyMode * outsideIDdamagePotential;   

        debprint ("Bombable: Heavy weapon or bomb, direct hit, damaging");
           
      }    

      #debprint ("Bombable: Damaging hit, "~ " Distance= ", closestApproach_m, "by ", impactNodeName~ " on ", myNodeName," terrain=", impactTerrain, " damageRadius=", damageRadius_m," weaponDamageCapability ", weaponDamageCapability, " damagePotential ", damagePotential, " OIdP ", outsideIDdamagePotential, " Par damage: ", weaponDamageCapability * vuls.damageVulnerability);

			damAdd=add_damage( damageCaused, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m  );
      
      #checking/setting this prevents the same splash from being repeatedly re-drawn
      # as we check the impact from different AI objects      

          
      if (damageCaused>0 ) {
        #places a gun flack at the hit location 
        
        if (myNodeName=="") { 
        #case of MainAC, we just draw the impact where FG has detected it

          exit_test_impact(impactNodeName, myNodeName);        
                
        } else {       
        #case of AI or MP Aircraft, we draw it at point of closest impact
            
          #Code below calculates <crossProdObj_Imp>, the vector from the 
          #   object location to the closest approach/impact point
          # Vector <crossProd> has the right magnitude but is perpendicular to the plane
          # containing the impact detection point, the closest approach point, and the
          # object location.  Doing the cross product of <crossProd> with <impactorDirection> (which
          # is a unit vector in the direction of impactor travel) gives the vector
          # in the direction from object location to impact closest approach point, and (since <impactorDirection> is the unit vector and <crossProd>'s magnitude is the distance from 
          # the object location to the closest approach point, that vector's magnitude is the
          # distance from object location to closest approach point. 
          # 
          # Between this and <impactorDirection> we have the exact location and the direction
          # of the closest impact point.  These two items together could be used to calculate specific damage,
          # systems affected, etc., by damage coming at a specific angle in a specific area.          
                 
          var crossProdObj_ImpX_m=impactorDirectionY*crossProdZ_m - impactorDirectionZ*crossProdY_m;
          var crossProdObj_ImpY_m=impactorDirectionZ*crossProdX_m - impactorDirectionX*crossProdZ_m;
          var crossProdObj_ImpZ_m=impactorDirectionX*crossProdY_m - impactorDirectionY*crossProdX_m;  
        
          debprint ("Bombable: Put splash direct hit");
          put_splash (impactNodeName, oLat_deg+crossProdObj_ImpY_m/m_per_deg_lat, oLon_deg+crossProdObj_ImpX_m/m_per_deg_lon,                         oAlt_m+crossProdObj_ImpZ_m,ballisticMass_lb, impactTerrain, 1, myNodeName);
      
          
        }                          
      }                      	
    	
  # end, case of direct hit
  } else { 
  # case of a near hit, on terrain, if it's a bomb we'll add damage
  # Some of the below is a bit forward thinking--it includes some damage elements to 1000 m 
  # or even more distance for very large bombs.  But up above via the quick lat/long calc 
  #  (for performance reasons) we're exiting immediately for impacts > 300 meters or so away.      

     #debprint ("near hit, not direct");
    if (myNodeName=="") { 
    #case of MainAC, we just draw the impact where FG has detected it,
    # not calculating any refinements, which just case problems in case of the 
    # mainAC, anyway.        

      exit_test_impact(impactNodeName, myNodeName);        
            
    } else {      
    #case of AI or MP aircraft, we draw the impact at point of closest approach 
  

        var impactSplashPlaced=getprop (""~impactNodeName~"/impact/bombable-impact-splash-placed");
        var impactRefinedSplashPlaced=getprop (""~impactNodeName~"/impact/bombable-impact-refined-splash-placed");
        #debprint("iSP=",impactSplashPlaced, " iLat=", iLat_deg);
        if ( (impactSplashPlaced==nil or impactSplashPlaced!=iLat_deg) 
             and (impactRefinedSplashPlaced==nil or impactRefinedSplashPlaced!=iLat_deg)
             and ballisticMass_lb>1.2) {
          var crossProdObj_ImpX_m=impactorDirectionY*crossProdZ_m - impactorDirectionZ*crossProdY_m;
          var crossProdObj_ImpY_m=impactorDirectionZ*crossProdX_m - impactorDirectionX*crossProdZ_m;
          var crossProdObj_ImpZ_m=impactorDirectionX*crossProdY_m - impactorDirectionY*crossProdX_m;  
           
          debprint ("Bombable: Put splash near hit > 1.2 ", ballisticMass_lb, " ", impactNodeName);
          put_splash (impactNodeName, 
                        oLat_deg+crossProdObj_ImpY_m/m_per_deg_lat, 
                        oLon_deg+crossProdObj_ImpX_m/m_per_deg_lon,
                        oAlt_m+crossProdObj_ImpZ_m, ballisticMass_lb, 
                        impactTerrain, 1, myNodeName );               
         }
     }    
     
   	 if (ballisticMass_lb>1.2) { 
      
        debprint ("Bombable: Close hit by bomb, "~ impactNodeName~ " on "~ myNodeName~ " Distance= "~ closestApproach_m ~ " terrain="~ impactTerrain~ " radius="~ damageRadius_m~" mass="~ballisticMass_lb);
    }      

     
     

    # check submodel blast effect distance.
    # different cases for each size of ordnance and distance of hit		
    if (ballisticMass_lb < 1.2 ) {
       #do nothing, just a small round hitting on terrain nearby
      
    } elsif (ballisticMass_lb < 10 and ballisticMass_lb >= 1.2 )  {
      if(closestApproach_m <= 10 + damageRadius_m)
				damAdd=add_damage(.1 * vuls.damageVulnerability * ballisticMass_lb / 10 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);    
      elsif((closestApproach_m > 10 + damageRadius_m) and (closestApproach_m < 30 + damageRadius_m)){
         var damFactor= (30-closestApproach_m)/30;
         if (damFactor<0) damFactor=0;

         if (rand()<damFactor) damAdd=add_damage(0.0002 * vuls.damageVulnerability * ballisticMass_lb/10* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }   
    
    } elsif  (ballisticMass_lb < 50 and ballisticMass_lb >= 10 ) {
			if(closestApproach_m <= .75 + damageRadius_m)
				damAdd=add_damage(.3 * vuls.damageVulnerability * ballisticMass_lb /50 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > .75 + damageRadius_m) and (closestApproach_m <= 10 + damageRadius_m))
			  damAdd=add_damage(.0001 * vuls.damageVulnerability * ballisticMass_lb /50 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);

			elsif((closestApproach_m > 10 + damageRadius_m) and (closestApproach_m < 30 + damageRadius_m))
				damAdd=add_damage(0.00005 * vuls.damageVulnerability * ballisticMass_lb /50 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 30 + damageRadius_m) and (closestApproach_m < 60 + damageRadius_m)){
         var damFactor= (60-closestApproach_m)/60;
         if (damFactor<0) damFactor=0;

         if (rand()<damFactor) damAdd=add_damage(0.0002 * vuls.damageVulnerability * ballisticMass_lb/50* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }    
      else{
         var damFactor= (100-closestApproach_m)/100;
         if (damFactor<0) damFactor=0;
         if (rand()<damFactor) damAdd=add_damage(0.0001 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }    

		} elsif (ballisticMass_lb < 200 and ballisticMass_lb >= 50 ) {
			if(closestApproach_m <= 1.5 + damageRadius_m)
				damAdd=add_damage(1 * vuls.damageVulnerability * ballisticMass_lb/200  * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 1.5 + damageRadius_m) and (closestApproach_m <= 10 + damageRadius_m))
			  damAdd=add_damage(.01 * vuls.damageVulnerability * ballisticMass_lb /200 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
				
			elsif((closestApproach_m > 10 + damageRadius_m) and (closestApproach_m < 30 + damageRadius_m))
				damAdd=add_damage(0.0001 * vuls.damageVulnerability * ballisticMass_lb/200* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      elsif((closestApproach_m > 30 + damageRadius_m) and (closestApproach_m < 60 + damageRadius_m)){
         var damFactor= (75-closestApproach_m)/75;
         if (damFactor<0) damFactor=0;

         if (rand()<damFactor) damAdd=add_damage(0.0002 * vuls.damageVulnerability * ballisticMass_lb/200 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }   
				 
      else{
         var damFactor= (100-closestApproach_m)/100;
         if (damFactor<0) damFactor=0;
         if (rand()<damFactor) damAdd=add_damage(0.0001 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }    

		 } elsif ((ballisticMass_lb >= 200) and (ballisticMass_lb < 350)) {
			# Mk-81 class
			# Source: http://en.wikipedia.org/wiki/General-purpose_bomb			
			# Estimated: crater = 2 m, lethal blast=12 m, casualty radius (50%)=25 m, blast shrapnel ~70m, fragmentation ~= 250 m  	
			# All bombs adjusted downwards outside of crater/lethal blast distance, 
			# based on flight testing plus:
			# http://www.f-16.net/f-16_forum_viewtopic-t-10801.html            		

			if(closestApproach_m <= 2 + damageRadius_m)
				damAdd=add_damage(2 * vuls.damageVulnerability * ballisticMass_lb/350 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 2 + damageRadius_m) and (closestApproach_m <= 12 + damageRadius_m))
			  damAdd=add_damage(.015 * vuls.damageVulnerability * ballisticMass_lb /350 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 12 + damageRadius_m) and (closestApproach_m < 25 + damageRadius_m))
				damAdd=add_damage(0.0005 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      elsif((closestApproach_m > 25 + damageRadius_m) and (closestApproach_m < 70 + damageRadius_m))  {
         var damFactor= (90-closestApproach_m)/90;
         if (damFactor<0) damFactor=0;

         if (rand()<damFactor) damAdd=add_damage(0.0002 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }   
      else{
         var damFactor= (250-closestApproach_m)/250;
         if (damFactor<0) damFactor=0;
         if (rand()<damFactor) damAdd=add_damage(0.0001 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }    

		} elsif((ballisticMass_lb >= 350) and (ballisticMass_lb < 750)) {
			# Mk-82 class  (500 lb)
			# crater = 4 m, lethal blast=20 m, casualty radius (50%)=60 m, blast shrapnel ~100m, fragmentation ~= 500 m  			
			# http://www.khyber.org/publications/006-010/usbombing.shtml			
			if(closestApproach_m <= 4 + damageRadius_m )
				damAdd=add_damage(4 * vuls.damageVulnerability * ballisticMass_lb /750 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m); 
			elsif((closestApproach_m > 4 + damageRadius_m) and (closestApproach_m <= 20 + damageRadius_m))
			  damAdd=add_damage(.02 * vuls.damageVulnerability * ballisticMass_lb /750 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 20 + damageRadius_m) and (closestApproach_m <= 60 + damageRadius_m))
				damAdd=add_damage(0.001 * vuls.damageVulnerability * ballisticMass_lb /750 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 60 + damageRadius_m) and (closestApproach_m <= 100 + damageRadius_m)) {
         var damFactor= (120-closestApproach_m)/120;
         if (damFactor<0) damFactor=0;

         if (rand()<damFactor) damAdd=add_damage(0.0002 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }   
				
      else{
         var damFactor= (500-closestApproach_m)/500;
         if (damFactor<0) damFactor=0;
         if (rand()<damFactor) damAdd=add_damage(0.0001 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }         
      
		} elsif((ballisticMass_lb >= 750) and (ballisticMass_lb < 1500)) {
			# Mk-83 class (1000 lb)
			# crater = 11 m, lethal blast~=27 m, casualty radius (50%)~=230 m, blast shrapnel 190m, fragmentation 1000 m 			
			# http://www.khyber.org/publications/006-010/usbombing.shtml			

			if(closestApproach_m <= 11 + damageRadius_m )
				damAdd=add_damage(8 * vuls.damageVulnerability * ballisticMass_lb/1500 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m); 
			elsif((closestApproach_m > 11 + damageRadius_m) and (closestApproach_m <= 27 + damageRadius_m))
			  damAdd=add_damage(.02 * vuls.damageVulnerability * ballisticMass_lb /1500 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);

			elsif((closestApproach_m > 27 + damageRadius_m) and (closestApproach_m <= 190 + damageRadius_m))
				damAdd=add_damage(0.001 * vuls.damageVulnerability * ballisticMass_lb/1500 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 190 + damageRadius_m) and (closestApproach_m <= 230 + damageRadius_m)){
         var damFactor= (230-closestApproach_m)/230;
         if (damFactor<0) damFactor=0;

         if (rand()<damFactor) damAdd=add_damage(0.0002 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }   	
				
      else {
         var damFactor= (1000-closestApproach_m)/1000;
         if (damFactor<0) damFactor=0;
         if (rand()<damFactor) damAdd=add_damage(0.0001 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }                           		

    } elsif(ballisticMass_lb >= 1500 ) {
			# Mk-84 class (2000 lb) and upper
			# crater = 18 m, lethal blast=34 m, casualty radius (50%)=400 m, blast shrapnel 380m, fragmentation = 1000 m 			
			# http://www.khyber.org/publications/006-010/usbombing.shtml			

			if(closestApproach_m <= 18 + damageRadius_m )
				damAdd=add_damage(16 * vuls.damageVulnerability * ballisticMass_lb/3000 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m); 
			elsif((closestApproach_m > 18 + damageRadius_m) and (closestApproach_m <= 34 + damageRadius_m))
			  damAdd=add_damage(.02 * vuls.damageVulnerability * ballisticMass_lb /3000 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);

			elsif((closestApproach_m > 34 + damageRadius_m) and (closestApproach_m <= 380 + damageRadius_m))
				damAdd=add_damage(0.001 * vuls.damageVulnerability * ballisticMass_lb/3000 * easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
			elsif((closestApproach_m > 380 + damageRadius_m) and (closestApproach_m <= 500 + damageRadius_m)){
         var damFactor= (500-closestApproach_m)/500;
         if (damFactor<0) damFactor=0;

         if (rand()<damFactor) damAdd=add_damage(0.0002 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }   	
				
      else {
         var damFactor= (1500-closestApproach_m)/1500;
         if (damFactor<0) damFactor=0;
         if (rand()<damFactor) damAdd=add_damage(0.0001 * vuls.damageVulnerability * ballisticMass_lb/350* easyMode, myNodeName, "weapon", impactNodeName, ballisticMass_lb, iLat_deg, iLon_deg, iAlt_m);
      }           
		
    }
		
	}

	var node = props.globals.getNode(myNodeName);
  var type=node.getName();

  if ( type != "multiplayer" and myNodeName!="" ) {	
    	#any impacts somewhat close to us, we start dodging - if we're a good pilot.
    
      var skill = calcPilotSkill (myNodeName);
    	if ( closestApproach_m < 500 and rand() < skill/14 ) dodge (myNodeName);
    	
      #but even numbskull pilots start dodging if there is a direct hit!
      # Unless distracted ((rand()< .20 - 2*skill/100)) is a formula for 
      #       distraction, assumed to be lower for more skilled pilots      
      
    	elsif ( damAdd>0 and (rand()< .20 - 2*skill/100) ) dodge (myNodeName); 
	}
  
}


#########################################################
# FUNCTION speed_adjust
# 
# adjusts airspeed of an AI object depending on whether it is climbing, diving,
# or ~level flight
#
# TODO: We could also adjust speed based on the roll angle or turn rate (turning
# too sharp reduces speed and this is one of the primary constraints on sharp
# turns in fighter aircraft)
# 
var speed_adjust = func (myNodeName, time_sec ){

  var onGround=getprop (""~myNodeName~"/bombable/on-ground");
  if (onGround) return;
  
  var stalling=0;
  var vels = attributes[myNodeName].velocities;
  
  airspeed_kt=getprop (""~myNodeName~"/velocities/true-airspeed-kt");
  if (airspeed_kt<=0) airspeed_kt=.000001; #avoid the div by zero issue
  airspeed_fps = airspeed_kt * knots2fps;
  vertical_speed_fps=getprop (""~myNodeName~"/velocities/vertical-speed-fps");
  
  var vels = attributes[myNodeName].velocities;
  var maxSpeed_kt = vels.maxSpeed_kt;
  if (maxSpeed_kt<=0) maxSpeed_kt=90;

  #The AI airspeed_kt is true airspeed (TAS) which is quite different from
  # indicated airspeed (IAS) at altitude.  
  # Stall speed is (approximately) constant in IAS, regardless of altitude,
  # so it is best to use IAS to determine the real stall speed.
  # By contrast, max Speed (Vne) seems more independent of altitude                                                   

  var minSpeed_kt = trueAirspeed2indicatedAirspeed (myNodeName, vels.minSpeed_kt);
  if (minSpeed_kt<=0) minSpeed_kt=40;
  sin_pitch=vertical_speed_fps/airspeed_fps;

  if (sin_pitch > 1) sin_pitch=1;
  if (sin_pitch < -1) sin_pitch=-1;
  
  var add_velocity_fps=0;
  var termVel_kt=0;
  
  if (getprop(""~myNodeName~"/bombable/attack-inprogress") or 
        getprop ( ""~myNodeName~"/bombable/dodge-inprogress") ) {

      targetSpeed_kt=vels.attackSpeed_kt; 

  } elsif ( stores.fuelLevel (myNodeName) < .2 ) {
    
    #reduced speed if low on fuel
    targetSpeed_kt=(vels.cruiseSpeed_kt + vels.minSpeed_kt )/2;
  
  }
  else {
  
      targetSpeed_kt=vels.cruiseSpeed_kt;
  }
  
  #some failsafe defaults; if we don't have min < target < max
  # our formulas below can fail horribly  
  if (targetSpeed_kt<=minSpeed_kt) targetSpeed_kt=minSpeed_kt+20;
  if (maxSpeed_kt<=targetSpeed_kt) maxSpeed_kt=targetSpeed_kt*1.5;
  
  #reduce A/C speed when turning at a high roll rate
  #this is a bit of a kludge, but reduces target speed from attack
  #to cruise speed as roll degrees goes from 70 to 80, which about 
  #matches the performance of Zero & F6F in FG.
  #this probably needs to be set/individualized per AC
  var sustainRollLimit_deg=70;
  var sustainRollLimitTransition_deg=10;
  var currRoll_deg=getprop(""~myNodeName~"/orientation/roll-deg");  
  if (math.abs(currRoll_deg)>sustainRollLimit_deg) {
    if (math.abs(currRoll_deg)>sustainRollLimit_deg + sustainRollLimitTransition_deg)
      targetSpeed_kt=vels.cruiseSpeed_kt; 
    else {
       targetSpeed_kt=(vels.attackSpeed_kt - vels.cruiseSpeed_kt ) 
          * (currRoll_deg - sustainRollLimit_deg)   
          + vels.cruiseSpeed_kt;
    }
  }
  
  #level flight, we tend towards our cruise or attack speed
  # we're calling less then 5 in 128 climb or dive, level flight  
  if (math.abs(sin_pitch) < 5/128 ) {
    
    if (targetSpeed_kt<=0) targetSpeed_kt=50;  
    if (airspeed_kt<targetSpeed_kt) {
       var calcspeed_kt=airspeed_kt;
       if (calcspeed_kt<minSpeed_kt) calcspeed_kt=minSpeed_kt;
       var fact = 1-(calcspeed_kt-minSpeed_kt)/(targetSpeed_kt-minSpeed_kt);
    } else {

       var calcspeed_kt=airspeed_kt;
       if (calcspeed_kt>maxSpeed_kt) calcspeed_kt=maxSpeed_kt;
       var fact = 1-(maxSpeed_kt-calcspeed_kt)/(maxSpeed_kt-targetSpeed_kt);
    
    }   
    
    #the / 70 may require tweaking or customization. This basically goes to how
    # much acceleration the AC has.   /70 matches closely the A6M2 Zero's
    # acceleration during level flight     
    add_velocity_fps =math.sgn (targetSpeed_kt - airspeed_kt) * math.pow(math.abs(fact),0.5) * targetSpeed_kt * time_sec * knots2fps / 70 ; 
    termVel_kt=targetSpeed_kt;
    #debprint ("Bombable: Speed Adjust, level:", add_velocity_fps*fps2knots );
    
  
  } elsif(sin_pitch>0 ) {
  # climbing, so we reduce our airspeed, tending towards V (s)
      deltaSpeed_kt=airspeed_kt-minSpeed_kt;  
      
      #debprint ("Bombable: deltaS",deltaSpeed_kt, " maxS:", maxSpeed_kt, " minS:", minSpeed_kt," grav:",  grav_fpss, " timeS:", time_sec," sinP",  sin_pitch   );
      #add_velocity_fps=-(deltaSpeed_kt/(maxSpeed_kt-minSpeed_kt))*grav_fpss*time_sec*sin_pitch*10;
      # 
      
      #termVel_kt is the terminal velocity for this particular angle of attack
      # if we could get a more accurate formulate for the terminal velocity for
      # each angle of attack this would be even more realistic
      # cal ranges 0-1 (though cal 1 . . . infinity is possible)
      # and generally smaller cal makes the terminal velocity
      # slower for lower angles of attack.  so if your aircraft is going too 
      # fast when climbing (compared with the similar 'real' aircraft in 
      #     bombable)
      # make cal smaller.  cal=.13 seems about right for 
      #       Sopwith Camel, with vel1^2/vel2^2  for Zero, cal=.09 and ^3/^3             
      #var cal=.09;      
      #termVel_kt=targetSpeed_kt - math.pow(math.abs(sin_pitch),cal)*(targetSpeed_kt-minSpeed_kt);
                                   
      termVel_kt=targetSpeed_kt - vels.climbTerminalVelocityFactor*math.abs(sin_pitch); 
      
      #In the case of diving, we're going to assume that the pilot will cut
      # power, add slats, add flaps, or whatever to keep the speed below
      # Vne.  However in the case of climbing, there is no such limit.
      # If you keep climbing you will eventually reach vel=0 and even negative
      # velocity.                        
      #if (termVel_kt < minSpeed_kt) termVel_kt=minSpeed_kt;
                      
      vel1=maxSpeed_kt-airspeed_kt;
      vel2=maxSpeed_kt-termVel_kt;
      
      add_velocity_fps= - (1-math.abs(vel1/vel2))*grav_fpss*time_sec; 
      
  
                
      #debprint ("Bombable: Speed Adjust, climbing:", add_velocity_fps*fps2knots );
     
  } elsif (sin_pitch<0 ){
  # diving, so we increase our airspeed, tending towards the V(ne)
      
      #termVel_kt is the terminal velocity for this particular angle of attack
      # if we could get a more accurate formulate for the terminal velocity for
      # each angle of attack this would be even more realistic     
      # 
      # cal generally ranges from 0 to infinity and the higher cal the slower
      # terminal velocity for low angles of attack.  If your aircraft don't
      # gain enough speed on dive, make cal smaller, down to 1 or possibly 
      # even below. cal=1.5 seems about right for Sopwith Camel.a^2/Vt^2 and g*t*1     
      # For Zero, cal=1.0, a^3/Vt^3 and g*t*2 is a better fit.                         
      #var cal=1.0;                   
      #termVel_kt=math.pow (math.abs(sin_pitch), cal)*(maxSpeed_kt-targetSpeed_kt) + targetSpeed_kt;
      
      termVel_kt=targetSpeed_kt + vels.diveTerminalVelocityFactor*math.abs(sin_pitch);
      
      #We're assuming the pilot will take action to keep it below maxSpeed_kt,
      # such as reducing engine, slats, flaps, etc etc etc.  In some cases this
      # may not be realistic but              
      if (termVel_kt>maxSpeed_kt) termVel_kt=maxSpeed_kt; 
                   
      add_velocity_fps=(1-math.abs(airspeed_kt/termVel_kt))*grav_fpss*time_sec;
      #debprint ("Bombable: Speed Adjust, diving:", add_velocity_fps*fps2knots );
  
  }   
  
  #if we're above maxSpeed we make a fairly large/quick correction
  # but only if it is larger (in negative direction) than the regular correction  
  if (airspeed_kt>maxSpeed_kt) {
     maxS_add_velocity_fps=(maxSpeed_kt-airspeed_kt)/10*time_sec*knots2fps;
     if ( maxS_add_velocity_fps < add_velocity_fps) 
        add_velocity_fps =maxS_add_velocity_fps;
  }      
  
  
  
  #debprint ("Bombable: Speed Adjust:", add_velocity_fps*fps2knots, " TermVel:", termVel_kt, "sinPitch:", sin_pitch );
  var finalSpeed_kt=airspeed_kt + add_velocity_fps*fps2knots;
  #Zero/negative airspeed causes problems . . .  
  if (finalSpeed_kt< minSpeed_kt / 3) finalSpeed_kt=minSpeed_kt/3;
  setprop (""~myNodeName~"/controls/flight/target-spd", finalSpeed_kt);
  setprop (""~myNodeName~"/velocities/true-airspeed-kt", finalSpeed_kt);
  
  if (finalSpeed_kt < minSpeed_kt) {
     stalling = 1;
     
     #When we stall & both vertical speed & airspeed go to zero, FG just flips 
     # out.  If we're stalling then gravity takes over, no lift, so we make 
     # that happen here.
     vertical_speed_fps -= grav_fpss * time_sec;
     setprop ( ""~myNodeName~"/velocities/vertical-speed-fps", vertical_speed_fps );
     
  } 
  
  #The vertical speed should never be greater than the airspeed, otherwise 
  #   something (ie one of the bombable routines) is adding in extra
  #   energy to the AC.  
  finalSpeed_fps=finalSpeed_kt*knots2fps;
  if (math.abs(vertical_speed_fps)>math.abs(finalSpeed_fps)) 
      setprop (""~myNodeName~"/velocities/vertical-speed-fps",math.sgn (vertical_speed_fps) * math.abs(finalSpeed_fps));
  
  setprop ("" ~ myNodeName ~ "/bombable/stalling", stalling);
  
  #make the aircraft's pitch match it's vertical velocity; otherwise it looks fake
  setprop (""~myNodeName~"/orientation/pitch-deg", math.asin(sin_pitch)* rad2degrees);


}

var speed_adjust_loop = func ( id, myNodeName, looptime_sec) {
   var loopid = getprop(""~myNodeName~"/bombable/loopids/speed-adjust-loopid"); 
   id == loopid or return;
   #debprint ("aim-timer");
    
   settimer (  func { speed_adjust_loop (id, myNodeName, looptime_sec)}, looptime_sec);

   #debprint ("weapons_loop starting");

   if (! getprop (bomb_menu_pp~"ai-aircraft-attack-enabled") or ! getprop(bomb_menu_pp~"bombable-enabled") ) return;
   
   speed_adjust (myNodeName, looptime_sec);

}

######################################################################
# FUNCTION do_acrobatic_loop_loop
# The settimer loop to do an acrobatic loop, up or down, or part of a loop
# 

var do_acrobatic_loop_loop = func (id, myNodeName, loop_time=20, full_loop_steps=100, exit_steps=100, direction="up", rolldirenter = "cc", rolldirexit="ccw", vert_speed_add_kt=225, loop_count=0  ){

    #same loopid as roll so one can interrupt the other
    var loopid = getprop(""~myNodeName~"/bombable/loopids/roll-loopid"); 
  	id == loopid or return; 
    
    if (direction=="up") var dir=1; 
    else var dir = -1;                 
  	
    var vert_speed_add_fps=vert_speed_add_kt*knots2fps;
    #we want to accelerate vertically by vert_speed_add over the first 1/4 of the loop; then back to 0 over the next 1/4 of the loop, then to - vert_speed_add
    # over the next 1/4 of the loop, then back to 0 over the last 1/4.  
    var vert_speed_add_per_step_fps = vert_speed_add_fps * 4 / full_loop_steps; 
  
    #we'll never put something greater than the AC's maxSpeed into the vertical
    # velocity  
    var vels = attributes[myNodeName].velocities;
    var alts = attributes[myNodeName].altitudes;
    
    maxSpeed_fps=vels.maxSpeed_kt * knots2fps;
    
    #or greater than the current speed
    currSpeed_kt=getprop (""~myNodeName~"/velocities/true-airspeed-kt");
    currSpeed_fps=currSpeed_kt*knots2fps;
    
    currAlt_ft = getprop(""~myNodeName~"/position/altitude-ft");
    currAlt_m=currAlt_ft * feet2meters;
    
    
    #we use main AC elev as a stand-in for our own elevation, since the elev
    # function is so slow.  A bit of a kludge.    
    mainACElev_m=getprop ("/position/ground-elev-m");
    
    var stalling=getprop ("" ~ myNodeName ~ "/bombable/stalling");
    
    #if we stall out or exceed the maxSpeed or lower than minimum allowed altitude
    #    then we terminate the loop & the dodge
    if (stalling or currSpeed_kt>vels.maxSpeed_kt or currAlt_m - mainACElev_m < alts.minimumAGL_m ) {
       setprop(""~myNodeName~"/bombable/dodge-inprogress", 0);
       return;
    }
    
      
    loop_count+=1;
  	if (loop_count<=exit_steps ) settimer (func { do_acrobatic_loop_loop(id, myNodeName, loop_time, full_loop_steps, exit_steps, direction, rolldirenter, rolldirexit,vert_speed_add_kt, loop_count);}, loop_time/full_loop_steps);
  	
  	var curr_vertical_speed_fps= getprop ("" ~ myNodeName ~ "/velocities/vertical-speed-fps");
  	var curr_acrobat_vertical_speed_fps = getprop ("" ~ myNodeName ~ "/velocities/bombable-acrobatic-vertical-speed-fps");
  	
  	
  	
  	if (loop_count<full_loop_steps/4 or loop_count>=full_loop_steps*3/4) var localdir=1;
  	else  var localdir=-1;
    
    curr_acrobat_vertical_speed_fps = curr_acrobat_vertical_speed_fps + localdir* dir * vert_speed_add_per_step_fps;
     
    var proposed_vertical_speed_fps=curr_vertical_speed_fps + localdir * dir * vert_speed_add_per_step_fps;
  
  
    #we only add the adjustments to the vertical speed when the amount 
    # it 'should be' is greater (in magnitude) than the current vertical speed   
    #var sgn = math.sgn (curr_acrobat_vertical_speed_fps);
    #if ( sgn * curr_acrobat_vertical_speed_fps >=  sgn * proposed_vertical_speed_fps) setprop ("" ~ myNodeName ~ "/velocities/vertical-speed-fps", proposed_vertical_speed_fps);    
    setprop ("" ~ myNodeName ~ "/velocities/bombable-acrobatic-vertical-speed-fps", curr_acrobat_vertical_speed_fps);
      
    debprint ("Bombable: Acrobatic loop, ideal vertfps: ", curr_acrobat_vertical_speed_fps );
      
    #The FG vert-speed prop sort of wiggles around for various reasons,
    # so we are just basically going to force it where we want it, no
    # matter what.        
    # However, with these limits:      

    #The vert speed should never be set larger than the maxSpeed
    curr_acrobat_vertical_speed_fps = checkRange (curr_acrobat_vertical_speed_fps, -maxSpeed_fps, maxSpeed_fps, curr_acrobat_vertical_speed_fps);
    
    #The vert speed should never be set larger than the current speed
    # We're just changing the direction of the motion here, not adding any
    # new speed or energy.        
    curr_acrobat_vertical_speed_fps = checkRange (curr_acrobat_vertical_speed_fps, -currSpeed_fps, currSpeed_fps, curr_acrobat_vertical_speed_fps);
    
    #To avoid weird looking bumpiness, we're never going to change the current vert speed by more than 2X vert_speed_add_fps at a time.  
    curr_acrobat_vertical_speed_fps = checkRange (curr_acrobat_vertical_speed_fps, 
      curr_vertical_speed_fps - 2*vert_speed_add_per_step_fps, 
      curr_vertical_speed_fps + 2*vert_speed_add_per_step_fps, 
      curr_acrobat_vertical_speed_fps);
    
    setprop ("" ~ myNodeName ~ "/velocities/vertical-speed-fps", curr_acrobat_vertical_speed_fps);
    debprint ("Bombable: Acrobatic loop, actual vertfps: ", curr_acrobat_vertical_speed_fps, "previous vertspd:",  curr_vertical_speed_fps);
    
    #target-alt will affect the vert speed unless we keep it close to current alt
    setprop (""~myNodeName~"/controls/flight/target-alt", currAlt_ft);
    
    # AI aircraft don't take kindly to flying upside down
    # so we just change their heading angle to roll them right-side up instead.
    # However, instead of just suddenly flipping by 180 degrees we do it 
    # gradually over a number of steps.        
    var turn_steps=full_loop_steps/3;
    
    #The roll direction is a bit complicated because it is actually heading dir
    # and so it switches depending on whether pitch is positive or negative    
    rollDirEnterMult=dir;
    if (rolldirenter == "ccw") rollDirEnterMult=-dir; 
    rollDirExitMult=-dir;
    if (rolldirexit == "ccw") rollDirExitMult=dir;
    
    if (loop_count >= round(full_loop_steps/4) - turn_steps/2 and loop_count < round(full_loop_steps/4) + turn_steps/2 ){
        var curr_heading_deg= getprop ("" ~ myNodeName ~ "/orientation/true-heading-deg");
        setprop ("" ~ myNodeName ~ "/orientation/true-heading-deg", curr_heading_deg + rollDirEnterMult * 180/turn_steps);
    }  
    
    if (loop_count >= round(3*full_loop_steps/4) - turn_steps/2 and loop_count < round(3*full_loop_steps/4) + turn_steps/2 ){
      var curr_heading_deg= getprop ("" ~ myNodeName ~ "/orientation/true-heading-deg");
      setprop ("" ~ myNodeName ~ "/orientation/true-heading-deg", curr_heading_deg + rollDirExitMult* 180/turn_steps);
    }  

}

##############################
# FUNCTION do_acrobatic_loop
# 

var do_acrobatic_loop = func (myNodeName, loop_time=20, full_loop_steps=100, exit_steps=100,  direction="up", rolldirenter = "cc", rolldirexit="ccw", vert_speed_add_kt=nil ){
  
  debprint ("Bombable: Starting acrobatic loop for ", myNodeName, " ", loop_time, " ",full_loop_steps, " ",exit_steps,  " ",direction, " ",vert_speed_add_kt );
  setprop(""~myNodeName~"/bombable/dodge-inprogress", 1);
  settimer ( func {setprop(""~myNodeName~"/bombable/dodge-inprogress", 0);
               }, loop_time );

  #loopid same as other roll type maneuvers because only one can 
  #   happen at a time
  var loopid = getprop(""~myNodeName~"/bombable/loopids/roll-loopid");
  if (loopid==nil) loopid=0; 
  loopid +=1;
  setprop(""~myNodeName~"/bombable/loopids/roll-loopid", loopid);
  
  if (vert_speed_add_kt==nil or vert_speed_add_kt<=0) {
   
   #this basically means, convert all of the AC's current forward velocity
   # into vertical velocity.  100% of the airspeed seems too much so we're 
   # trying70%       
   vert_speed_add_kt=.70*getprop (""~myNodeName~"/velocities/true-airspeed-kt");
  
  }
  
  setprop ("" ~ myNodeName ~ "/velocities/bombable-acrobatic-vertical-speed-fps", 0);
  #experimental - trying starting all acro maneuvers with 0 vert speed
  #setprop ("" ~ myNodeName ~ "/velocities/vertical-speed-fps", 0);

  #target-alt will affect the vert speed unless we keep it close to current alt  
  currAlt_ft = getprop(""~myNodeName~"/position/altitude-ft");
  setprop (""~myNodeName~"/controls/flight/target-alt", currAlt_ft );
  
  do_acrobatic_loop_loop(loopid, myNodeName, loop_time, full_loop_steps, exit_steps, direction, rolldirenter, rolldirexit, vert_speed_add_kt,  0 );


}               


##################################################################
# Choose an acrobatic loop more or less randomly
#
var choose_random_acrobatic = func (myNodeName){

 #get the object's initial altitude
 var lat = getprop(""~myNodeName~"/position/latitude-deg");
 var lon = getprop(""~myNodeName~"/position/longitude-deg");
 var elev_m=elev (lat, lon) * feet2meters;
 var alt_m=getprop ("/position/altitude-ft") * feet2meters;
 var altAGL_m=alt_m-elev_m;
 
 var direction="up";
 if (altAGL_m>1333 and rand()>.5) direction="down";
 
 rolldirenter="cc";
 rolldirexit="cc";
 if (rand()>.5) rolldirenter="ccw";
 if (rand()>.5) rolldirexit="ccw"; 

 var skill = calcPilotSkill (myNodeName);
 var time = 12 + (7-skill)*2.5 + rand()*20;
 vels= attributes[myNodeName].velocities;
 var currSpeed_kt=getprop (""~myNodeName~"/velocities/true-airspeed-kt");         
 var maxTime=(currSpeed_kt-vels.minSpeed_kt*2.2)/vels.minSpeed_kt/2.2*25 + 12;
   
   if (time>maxTime) time=maxTime;

 
 #loops of various sizes & between 1/4 & 100% complete
 do_acrobatic_loop (myNodeName, time, 100, 25+(1-rand()*rand())*75, direction, rolldirenter, rolldirexit ); 
  
}

##################################################################
# Function choose_attack_acrobatic
# 
# Choose an acrobatic loop strategically at the beginning of an attack
# returns 1 if a loop was executed, 0 otherwise
#

var choose_attack_acrobatic = func (myNodeName, dist, myHeading_deg, 
    targetHeading_deg, courseToTarget_deg, deltaHeading_deg, currSpeed_kt, 
    skill, currAlt_m, targetAlt_m, elevTarget_m){
    
   var ret=1;
   
   var skill = calcPilotSkill (myNodeName);
   var time=12  + (7-skill)*2.5 + 30 * math.abs(currAlt_m-targetAlt_m)/10000;
   if (time>45) time=45;
   
   
   
   #at 125 kts we can do a 20 second loop; at 250 a 60 second loop, maximum.
   # TODO: Should be airplane specific or dependent on the AC's characteristics
   # somehow.  Formula below based on minSpeed_kt is the first try.
   vels= attributes[myNodeName].velocities;         
   var maxTime=(currSpeed_kt-vels.minSpeed_kt*2.2)/vels.minSpeed_kt/2.2*25 + 12;
   
   if (time>maxTime) time=maxTime;

      
   #loops only help if the target is behind us
   if ( math.abs(deltaHeading_deg) >= 100 ) { 
   
       var vels = attributes[myNodeName].velocities;
   
       #if we're going same direction as target and it is close behind
       # us we try a 3/4 loop to try to slip in right behind it       
       if ( math.abs(normdeg180(myHeading_deg-targetHeading_deg)) < 90 and 
          dist < currSpeed_kt * time / 3600 * nmiles2meters ) var steps = 85;
          
       #otherwise it is far behind us or headed in the opposite direction, we
       # just do an immelmann loop to get turned around in its direction          
       else var steps = 48;   
       
       #if target is above us or not enough room below for a loop, 
       # or going too fast to do a downwards loop,  we'll
       # loop upwards, otherwise downwards      
       var currElev_m=elev (any_aircraft_position(myNodeName).lat(),geo.aircraft_position(myNodeName).lon() )*feet2meters;        
       if ( currAlt_m-targetAlt_m < 0 or currAlt_m - currElev_m < 1333 or 
          currSpeed_kt > .8 * vels.maxSpeed_kt ) var direction="up";
       else var direction="down";
       
       #TODO: there is undoubtedly a best direction to choose for these, 
       # which would leave the AI AC aimed more directly at the Main AC,       
       # depending on the relative positions of Main & AI ACs       
       rolldirenter="cc";
       rolldirexit="cc";
       if (rand()>.5) rolldirenter="ccw";
       if (rand()>.5) rolldirexit="ccw"; 
       
       debprint ("Bombable: Attack acrobatic, ", steps, "/100 loop ", myNodeName, " ", direction," ", rolldirenter, " ", rolldirexit);
       do_acrobatic_loop (myNodeName, time, 100, steps, direction, rolldirenter , rolldirexit); 

       setprop ( ""~myNodeName~"/bombable/dodge-inprogress" , 1);
       settimer ( func {setprop(""~myNodeName~"/bombable/dodge-inprogress", 0);
               }, time );

        
   #the target is in front of us, so a loop really isn't going to help
   # we'll let the initial attack routine do its thing     
   } else {
   
     ret=0;
   
   }   
   
   
     
   return ret;  
    
}


#########################################################
#rudder_roll_climb - sets the rudder position/roll degrees
#roll degrees controls aircraft & rudder position
#and for aircraft, sets an amount of climb
#controls ships, so we just change both, to be safe
var rudder_roll_climb = func (myNodeName, degrees=15, alt_ft=-20, time=10, roll_limit_deg=85 ){

   debprint ("Bombable: rudder_roll_climb starting, deg:", degrees," time:", time);
   #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
   alts= attributes[myNodeName].altitudes;
   
   node= props.globals.getNode(myNodeName);
   var type=node.getName();
   

   #rudder/roll
   currRudder=getprop(""~myNodeName~"/surface-positions/rudder-pos-deg");
   if (currRudder==nil) currRudder=0;
   
   currRoll=getprop(""~myNodeName~"/controls/flight/target-roll");
   if (currRoll==nil) currRoll=0;
   

   #add our amount to any existing roll/rudder & set the new roll/rudder position
   
   
   #this massively speeds up turns vs FG's built-in AI's rather
   # sedate turns; turns to the selected roll value in 5 seconds
   # rolling degrees/2 seems to give a turn of about degrees      
   if (type=="aircraft" and math.abs(degrees) > 0.1 ) aircraftRoll (myNodeName, degrees, time, roll_limit_deg);
   
   #debprint ("Bombable: setprop 2218");
   setprop(""~myNodeName~"/surface-positions/rudder-pos-deg", currRudder + degrees);
   setprop(""~myNodeName~"/controls/flight/target-roll", currRoll + degrees);
   
   #altitude
   #This only works for aircraft but that's OK because it's not sensible 
   #for a ground vehicle or ship to dive or climb above or below ground/sea
   #level anyway (submarines excepted . . . but under current the FG AI system
   # it would have to be operated as an "aircraft", not a "ship", if it 
   # wants to be able to climb & dive). 
   var currAlt_ft= getprop(""~myNodeName~"/position/altitude-ft"); #where the object is, in ft
   if (currAlt_ft + alt_ft < alts.minimumAGL_ft ) alt_ft = alts.minimumAGL_ft;
   if (currAlt_ft + alt_ft > alts.maximumAGL_ft ) alt_ft = alts.maximumAGL_ft;
   
   #debprint ("Bombable: setprop 2232");          
   # 
   # we set the target altitude, unless we are stalling and trying to move
   # higher, then we basically stop moving up      
   var stalling=getprop ("" ~ myNodeName ~ "/bombable/stalling");
   if (!stalling or alt_ft<currAlt_ft) {       
       setprop (""~myNodeName~"/controls/flight/target-alt", alt_ft);
       aircraftSetVertSpeed (myNodeName, alt_ft, "atts" );
   } else {
       #case: stalling
       var newAlt_ft= currAlt_ft - rand()*20 ;
       setprop (""~myNodeName~"/controls/flight/target-alt", newAlt_ft );
       aircraftSetVertSpeed (myNodeName, newAlt_ft, "atts" );
   } 
   
     
       
   #debprint ("2495 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
   
   
      

   #debprint (myNodeName, " dodging ", degrees, " degrees ", alt_ft, " feet");
}

################################################################
#function makes an object dodge
#
var dodge = func(myNodeName) {
   
     #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
     if ( getprop ( ""~myNodeName~"/bombable/dodge-inprogress") == 1 ) {
        #debprint ("Bombable: Dodge temporarily locked for this object. ", myNodeName );
        return;
    }   
  	if (  ! getprop (bomb_menu_pp~"ai-aircraft-attack-enabled") 
          or getprop("" ~ myNodeName~"/bombable/attributes/damage")==1 
          or ! getprop(bomb_menu_pp~"bombable-enabled") ) 
          return; 
         
    node= props.globals.getNode(myNodeName);
    var type=node.getName();
    debprint ("Bombable: Starting Dodge", myNodeName, " type= ", type);
  
    #Don't change rudder/roll again until the delay     
    setprop ( ""~myNodeName~"/bombable/dodge-inprogress" , 1);
  
    evas= attributes[myNodeName].evasions;
     
   	#skill ranges 0-5; 0=disabled, so 1-5;
    var skill = calcPilotSkill (myNodeName);
  	if (skill<=.2) skillMult=3/0.2;
    else skillMult= 3/skill;

   
   #amount to dodge, up to dodgeMax_deg in either direction
   # (1-rand()*rand()) favors rolls towards the high end of the allowed range   
   dodgeAmount_deg=(evas.dodgeMax_deg-evas.dodgeMin_deg)*(1-rand()*rand())+evas.dodgeMin_deg;
   #cut the amount of dodging down some for less skilled pilots
   dodgeAmount_deg *= (skill+6)/12; 
   
   # If we're rolling hard one way then 'dodge' means roll the opposite way.
   # Otherwise we set the roll direction randomly according to the preferences 
   #    file   
   currRoll_deg=getprop(""~myNodeName~"/orientation/roll-deg");
   if (math.abs(currRoll_deg) > 30) dodgeAmount_deg = - math.sgn(currRoll_deg)* dodgeAmount_deg;
   else if (rand() > evas.dodgeROverLPreference_percent/100) dodgeAmount_deg = -dodgeAmount_deg;

   #we want to mostly dodge to upper/lower extremes of our altitude limits   
   var dodgeAltFact=1-rand()*rand()*rand();
   #worse pilots don't dodge as far
   dodgeAltFact*= (skill+3)/9;
   #the direction of the Alt dodge will favor the direction that has more
   # feet to dodge in the evasions definitions.  Some aircraft heavily favor
   # diving to escape, for instance.      
   var dodgeAltDirection=(evas.dodgeAltMax_ft - evas.dodgeAltMin_ft) * rand()+evas.dodgeAltMin_ft;
   
   #target amount to climb or drop
   if (dodgeAltDirection>=0)  
       dodgeAltAmount_ft=dodgeAltFact*evas.dodgeAltMax_ft;
   else     
       dodgeAltAmount_ft=dodgeAltFact*evas.dodgeAltMin_ft;
       
   debprint ("Bombable: Dodge alt:", dodgeAltAmount_ft, " degrees:", dodgeAmount_deg);
   var dodgeDelay=(evas.dodgeDelayMax_sec-evas.dodgeDelayMin_sec)*rand()+evas.dodgeDelayMin_sec;
   
   
   if (type=="aircraft") {
       if (evas.rollRateMax_degpersec==nil or evas.rollRateMax_degpersec<=0) 
          evas.rollRateMax_degpersec=40;
       var rollTime_sec= math.abs(dodgeAmount_deg/evas.rollRateMax_degpersec);
       dodgeDelay_remainder_sec=dodgeDelay-rollTime_sec;
       if (dodgeDelay_remainder_sec<0) dodgeDelay_remainder_sec=.1; 

       var currSpeed_kt=getprop (""~myNodeName~"/velocities/true-airspeed-kt");
       if (currSpeed_kt==nil) currSpeed_kt=0;
       
       #more skilled pilots to acrobatics more often
       # in the Zero 130 kt is about the minimum speed needed to 
       # complete a loop without stalling.  TODO: This may vary by AC.
       # This could be linked to stall speed and maybe some other things.
       # As a first trying we're going with 2X minSpeed_kt as the lowest 
       # loop speed.          
       vels= attributes[myNodeName].velocities;                                
       if (currSpeed_kt>2*vels.minSpeed_kt and rand()< skill/7 and skill>=3) {
         choose_random_acrobatic(myNodeName);
         return;
       }
         
       #set rudder or roll degrees to that amount
       rudder_roll_climb (myNodeName, dodgeAmount_deg, dodgeAltAmount_ft, rollTime_sec);

       dodgeVertSpeed_fps = 0;
       currRoll_deg=getprop (""~myNodeName~"/orientation/roll-deg");
       
       
       if ( dodgeAltAmount_ft > 0 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps * dodgeAltAmount_ft/evas.dodgeAltMax_ft);
       if ( dodgeAltAmount_ft < 0 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps * dodgeAltAmount_ft/evas.dodgeAltMin_ft ); 
       
       #velocities/vertical-speed-fps seems to be fps * 1000 for some reason?  At least, approximately, 300,000 seems to be about 300 fps climb, for instance.
       # and we reduce the amount of climb/dive possible depending on the current roll angle (can't climb/dive rapidly if rolled to 90 degrees . . . )    
       #dodgeVertSpeed_fps*=1000 * math.abs(math.cos(currRoll_deg/rad2degrees));
       #dodgeVertSpeed_fps*= math.abs(math.cos(currRoll_deg/rad2degrees)); 
       
       #vert-speed prob
       #just putting a large number directly into vertical-speed-fps makes the aircraft
       #jump up or down far too abruptly for realism
       #if (dodgeVertSpeed_fps!=0) setprop ("" ~ myNodeName ~ "/velocities/vertical-speed-fps", dodgeVertSpeed_fps);

      debprint ("Dodging: ", myNodeName, " ", dodgeAmount_deg, " ", dodgeAltAmount_ft, " ", dodgeVertSpeed_fps, "rollTime:",rollTime_sec, " dodgeDelay_remainder:",dodgeDelay_remainder_sec); 

      #Now hold the aircraft at this roll--otherwise the AI
      #will return it to near-level flight   

      settimer ( func { aircraftRoll (myNodeName, dodgeAmount_deg, dodgeDelay_remainder_sec, evas.dodgeMax_deg); }, rollTime_sec);
      
       
       
       # Roll/climb for dodgeDelay seconds, then wait dodgeDelay seconds (to allow
       # the aircraft's turn to develop from the roll).
       # After this delay FG's aircraft AI will automatically return
       # it to near-level flight        
       #        
       stores.reduceFuel (myNodeName, dodgeDelay ); #deduct the amount of fuel from the tank, for this dodge             
       settimer ( func {
                    setprop(""~myNodeName~"/bombable/dodge-inprogress", 0);
                    #This resets the aircraft to 0 deg roll (via FG's
                    # AI system target roll; leaves target altitude 
                    # unchanged  )
                    #rudder_roll_climb (myNodeName, -dodgeAmount_deg, dodgeAltAmount_ft, rollTime_sec);
       
                      } 
       , rollTime_sec+dodgeDelay_remainder_sec );
   
   } else {  #other types besides aircraft
  
       #set rudder or roll degrees to that amount
       rudder_roll_climb (myNodeName, dodgeAmount_deg, dodgeAltAmount_ft, dodgeDelay);
      
       
             # Roll/climb for dodgeDelay seconds, then wait dodgeDelay seconds (to allow the change in direction
             
       stores.reduceFuel (myNodeName, 2*dodgeDelay ); #deduct the amount of fuel from the tank, for this dodge                                                 
       settimer ( func {setprop(""~myNodeName~"/bombable/dodge-inprogress", 0);
               rudder_roll_climb (myNodeName, 0, 0, dodgeDelay );}, 2*dodgeDelay );
   
   }
   
}

###############################################
# FUNCTION getCallSign
# returns call sign for AI, MP, or Main AC
# If no callsign, uses one of several defaults
# 

var getCallSign = func ( myNodeName ) {

  #Main AC
  if (myNodeName=="") {
    callsign=getprop ("/sim/multiplay/callsign");
    if (callsign==nil) callsign=getprop ("/sim/aircraft");
    if (callsign==nil) callsign="";
  
  #AI or MP objects
  } else {  

    	var callsign=getprop(""~myNodeName~"/callsign");
      if (callsign==nil or callsign=="") callsign=getprop(""~myNodeName~"/name");
      if (callsign==nil or callsign=="") {
              node=props.globals.getNode(myNodeName);
              callsign=node.getName() ~ "[" ~ node.getIndex() ~ "]";
      }
  }    
  return callsign;
  

}  



################################################################
# function updates damage to the ai or main aircraft when a msg
# is received over MP 

#damageRise is the increase in damage sent by the remote MP aircraft
#damageTotal is the remote MP aircraft's current total of damage
# (This should always be <= our damage total, so it is a failsafe
# in case of some packet loss)
var mp_update_damage = func (myNodeName="", damageRise=0, damageTotal=0, smokeStart=0, fireStart=0, callsign="" ) {

  if (myNodeName=="") myNodeName="";
  
  #if (myNodeName=="") debprint ("Bombable: Updating main aircraft 2328");
  
  var damageValue = getprop(""~myNodeName~"/bombable/attributes/damage");
  if (damageValue == nil ) damageValue=0;
  
 	if (damageValue<damageTotal) {
   
    damageValue=damageTotal;
    #note- in sprintf, %d just trims the decimal to make an integer
    # whereas %1.0f rounds to zero decimal places
    msg = sprintf( "Damage for "~string.trim(callsign)~" is %1.0f%%", damageValue*100);
  
    if (myNodeName=="") selfStatusPopupTip (msg, 30); 
    else targetStatusPopupTip (msg, 30);
    debprint ("Bombable: " ~ msg ~ " (" ~ myNodeName ~ ")" );
     
  }
		
  #make sure it's in range 0-1.0
  if(damageValue > 1.0)
			damageValue = 1.0;
	elsif(damageValue < 0.0)
			damageValue = 0.0;
	
  setprop(""~myNodeName~"/bombable/attributes/damage", damageValue);
  
  if (smokeStart) startSmoke ("damagedengine", myNodeName); 
  else deleteSmoke("damagedengine", myNodeName);
  
  if (fireStart) startFire (myNodeName); 
  else deleteFire(myNodeName);
  
  
  
  if (damageValue >= 1 and damageRise > 0 ) { 
      #make the explosion
      var smokeStartsize=rand()*10 + 5;
      settimer (func {setprop ("/bombable/fire-particles/smoke-startsize", smokeStartsize); }, 2.5);#turn the big explosion off sorta quickly 
      
      #this was rem-ed out, not sure why, re-enabling it 2013/03/31
      explosiveMass_kg=getprop(""~myNodeName~"/bombable/attributes/vulnerabilities/explosiveMass_kg");
      # 
                  
      if (explosiveMass_kg==nil or explosiveMass_kg==0) explosiveMass_kg = 10000; 
      smokeMultiplier = math.log10(explosiveMass_kg) * 10;
      setprop ("/bombable/fire-particles/smoke-startsize", smokeStartsize * smokeMultiplier + smokeMultiplier * rand());


   }
   
}

################################################################
# function sends the main aircraft's current damage, smoke, fire 
# settings over MP.  This is is to update all other MP aircraft
# with this aircraft's current damage status.  Other aircraft 
# track the damage internally, but if a 3rd aircraft damages this 
# aircraft, or if damage is added due to fire, etc., then the
# only way other MP aircraft will know about the damage is via this
# update.
#  

var mp_send_main_aircraft_damage_update = func (damageRise=0 ) {

  if (!getprop(MP_share_pp)) return "";
  if (!getprop (MP_broadcast_exists_pp)) return "";
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;

  
  damageTotal=getprop("/bombable/attributes/damage");
  if (damageTotal==nil) damageTotal=0;
  smokeStart=getprop("/bombable/fire-particles/damagedengine-burning");
  if (smokeStart==nil) smokeStart=0;
  fireStart=getprop("/bombable/fire-particles/fire-burning");
  if (fireStart==nil) fireStart=0;
  #mp_send_damage("", damageRise, damageTotal, smokeStart, fireStart);
  
  callsign = getCallSign ("");

  var msg=damage_msg (callsign, damageRise, damageTotal, smokeStart, fireStart, 3);                   
    if (msg != nil and msg != "") {
      debprint ("Bombable MADU: MP sending: "~callsign~" "~damageRise~" "~damageTotal~" "~smokeStart~" "~fireStart~" "~msg);
      mpsend(msg);
    }

}

################################################################
# function adds damage to the main aircraft when a msg
# is received over MP or for any othe reason 
# 
# Also start smoke/fire if appropriate, and turn off engines/explode
# when damage reaches 100%.

#damageRise is the increase in damage sent by the remote MP aircraft
#damageTotal is the remote MP aircraft's current total of damage
# (This should always be <= our damage total, so it is a failsafe
# in case of some packet loss)
var mainAC_add_damage = func (damageRise=0, damageTotal=0, source="", message="") {

  var damageValue = getprop("/bombable/attributes/damage");
  if (damageValue == nil ) damageValue=0;
  
  prevDamageValue=damageValue;
  
 	if(damageValue < 1.0) 
		damageValue += damageRise;
		
  if (damageValue<damageTotal) damageValue=damageTotal;
		
  #make sure it's in range 0-1.0
  if(damageValue > 1.0)
			damageValue = 1.0;
	elsif(damageValue < 0.0)
			damageValue = 0.0;
	
  setprop("/bombable/attributes/damage", damageValue);
  
  damageIncrease=damageValue-prevDamageValue;
  
  if (damageIncrease>0)  {
      addMsg1="You've been damaged!";
      addMsg2="You are out of commission! Engines/Magnetos off!";
      if (message!="")  {
        addMsg1=message;
        addMsg2=message;
      }         
      if (damageValue < .01) msg= sprintf( addMsg1 ~ " Damage added %1.2f%% - Total damage %1.0f%%", damageIncrease*100 , damageValue*100 );
      elsif (damageValue < .1) msg= sprintf( addMsg1 ~ " Damage added %1.1f%% - Total damage %1.0f%%", damageIncrease*100 , damageValue*100); 
      elsif (damageValue < 1) msg= sprintf( addMsg1 ~ " Damage added %1.0f%% - Total damage %1.0f%%", damageIncrease*100, damageValue*100);
      else msg= sprintf( "======== " ~ addMsg2 ~ " Damage added %1.0f%% - Total damage %1.0f%% ========", damageIncrease*100, damageValue*100 ); 
      selfStatusPopupTip (msg, 15);
      debprint ("Bombable: " ~ msg );
       
      if (damageValue == 1) {
        #So that ppl know their engine/magneto has been switched off, so they'll
        #know they need to turn it back on.       
        settimer ( func {
            if (getprop("/controls/engines/engine[0]/magnetos")==0 ) {
              msg="======== Damage 100% - your engines and magnetos have been switched off ========"; 
              selfStatusPopupTip (msg, 10);
              debprint ("Bombable: " ~ msg );
            }  
        } , 15);
      }
  }
  
  
  #Update--we don't allow remote control of main aircraft's
  # fire/smoke any more.  Causes problems.  
  #if (smokeStart) startSmoke ("damagedengine", ""); 
  #else deleteSmoke("damagedengine", "");
  
  #if (fireStart) startFire (""); 
  #else deleteFire("");
  
  #start smoke/fires if appropriate
  # really we need some way to customize this for every aircraft
  # just as we do for AI/MP aircraft.  But in the meanwhile this will work:
  
  myNodeName=""; #main aircraft
  
  var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  var vuls= attributes[myNodeName].vulnerabilities;

  
        

		var fireStarted=getprop("/bombable/fire-particles/fire-burning");
		if (fireStarted == nil ) fireStarted=0;
   	var damageEngineSmokeStarted=getprop("/bombable/fire-particles/damagedengine-burning");
   	if (damageEngineSmokeStarted == nil ) damageEngineSmokeStarted = 0; 
   	
   	
   	
   	if (!damageEngineSmokeStarted and !fireStarted and damageIncrease > 0 and rand()*100 < vuls.engineDamageVulnerability_percent ) 
        startSmoke("damagedengine",myNodeName);
       

	  # start fire if there is enough damage AND if the damage is caused by the right thing (weapons, crash, but not.
	  # if a crash, always start a fire (sometimes we reach 100% damage, no fire,
	  # then crash later--so when we crash, always start fire regardless)     	  
		if( (  ( 
              damageValue >= 1 - vuls.fireVulnerability_percent/100 
              and damageIncrease > 0 and !fireStarted 
            ) and 
              (source=="weapons" or source=="crash" ) 
        ) or 
            (source=="crash" )
    ) {
		
		
		  debprint ("Bombable: Starting fire for main aircraft");
			
			#use small, medium, large smoke column depending on vuls.damageVulnerability
			#(high vuls.damageVulnerability means small/light/easily damaged while 
			# low vuls.damageVulnerability means a difficult, hardened target that should burn
			# more vigorously once finally on fire)   
			var fp="";                     			
			if (vuls.explosiveMass_kg < 1000 ) { fp="AI/Aircraft/Fire-Particles/fire-particles-very-small.xml"; }
			elsif (vuls.explosiveMass_kg > 5000 ) { fp="AI/Aircraft/Fire-Particles/fire-particles-small.xml"; }
			elsif (vuls.explosiveMass_kg > 50000 ) { fp="AI/Aircraft/Fire-Particles/fire-particles-large.xml"; }
			else {fp="AI/Aircraft/Fire-Particles/fire-particles.xml";} 
			
      startFire(myNodeName, fp); 
      #only one damage smoke at a time . . . 
      deleteSmoke("damagedengine",myNodeName);
      
      
      #fire can be extinguished up to MaxTime_seconds in the future,
      #if it is extinguished we set up the damagedengine smoke so 
      #the smoke doesn't entirely go away, but no more damage added
      if ( rand() * 100 < vuls.fireExtinguishSuccess_percentage ) {
      
         settimer (func { 
           deleteFire (myNodeName);
           startSmoke("damagedengine",myNodeName); 
           } ,            
           rand() * vuls.fireExtinguishMaxTime_seconds + 15 ) ;
      };
  }
  
  #turn off engines if appropriate
  if (damageValue >= 1 and (prevDamageValue < 1 or getprop("/controls/engines/engine[0]/magnetos") > 0 or getprop("/controls/engines/engine[0]/throttle") > 0 )) { 
  
      #turn off all engines
      #debprint ("Bombable: setprop 2553");
      setprop("/controls/engines/engine[0]/magnetos",0);
      setprop("/controls/engines/engine[0]/throttle",0);
      setprop("/controls/engines/engine[1]/magnetos",0);
      setprop("/controls/engines/engine[1]/throttle",0);
      setprop("/controls/engines/engine[2]/magnetos",0);
      setprop("/controls/engines/engine[2]/throttle",0);
      setprop("/controls/engines/engine[3]/magnetos",0);
      setprop("/controls/engines/engine[3]/throttle",0);
      debprint ("Main aircraft damage 100%, engines off, magnetos off");
      
      #if no smoke/fire yet, now is the time to start
      startSmoke ("damagedengine", ""); 
      if (source=="weapons" or source=="crash" ) startFire (""); 
      
      var smokeStartsize=rand()*10 + 5;
      settimer (func {setprop ("/bombable/fire-particles/smoke-startsize", smokeStartsize); }, 2.5);#turn the big explosion off sorta quickly 
      
      smokeMultiplier = math.log10(vuls.explosiveMass_kg) * 10;
      setprop ("/bombable/fire-particles/smoke-startsize", smokeStartsize * smokeMultiplier + smokeMultiplier * rand());

   }
   
   
   mp_send_main_aircraft_damage_update (damageRise);
   
   return damageIncrease;
   
   
}


#send the damage message via multiplayer
var mp_send_damage = func (myNodeName="", damageRise=0 ) {
      
      if (!getprop(MP_share_pp)) return "";
      if (!getprop (MP_broadcast_exists_pp)) return "";
      if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;      
      
      #this makes it the main aircraft if nodename=""
      if (myNodeName=="") myNodeName="";
      
      #messageType 1 is letting another MP aircraft know you have damaged it
      #messageType 3 is informing all other MP aircraft know about the main
      # aircraft's current damage, smoke, fire settings
      #                   
      messageType=1;
      if (myNodeName=="") messageType=3;                                                                           
      var damageValue = getprop(""~myNodeName~"/bombable/attributes/damage");
      if (damageValue==nil) damageValue=0;
      
      if (myNodeName==""){
        callsign=getprop ("/sim/multiplay/callsign");
      }else {
        callsign=getprop (""~myNodeName~"/callsign");
      }
      
      var callsign = getCallSign (myNodeName);
      
      var fireStart=getprop(""~myNodeName~"/bombable/fire-particles/fire-burning");
  		if (fireStart == nil ) fireStart=0;
     	var smokeStart=getprop(""~myNodeName~"/bombable/fire-particles/damagedengine-burning");
     	if (smokeStart == nil ) smokeStart = 0;
      # debprint ("Bombable MSD: Preparing to send MP damage update to "~callsign);       
      var msg=damage_msg (callsign, damageRise, damageValue, smokeStart, fireStart, messageType);
      
      if (msg != nil and msg != "") {
        debprint ("Bombable MSD: MP sending: "~callsign~" "~damageRise~" "~damageValue~" "~smokeStart~" "~fireStart~" "~messageType~" "~msg);
        mpsend(msg);                                                    
      }
             
}  

######################
# fireAIWeapon_stop: turns off one of the triggers in AI/Aircraft/Fire-Particles/projectile-tracer.xml
#
var fireAIWeapon_stop = func (id, myNodeName="") {

  var loopid = getprop(""~myNodeName~"/bombable/loopids/fireAIWeapon-loopid");
  if (loopid!=id) return;
  #if (myNodeName=="" or myNodeName=="environment") myNodeName="/environment";
  setprop(myNodeName ~"/bombable/fire-particles/ai-weapon-firing",0);

}

######################
# fireAIWeapon: turns on/off one of the triggers in AI/Aircraft/Fire-Particles/projectile-tracer.xml
# Using the loopids ensures that it stays on for one full second are the last time it was
# turned on.
# 
var fireAIWeapon = func (time_sec=1, myNodeName="") {

  #if (myNodeName=="" or myNodeName=="environment") myNodeName="/environment";
  setprop(""~myNodeName~"/bombable/fire-particles/ai-weapon-firing",1);
  var loopid=inc_loopid(myNodeName, "fireAIWeapon");
  settimer ( func { fireAIWeapon_stop(loopid,myNodeName)}, time_sec);

}

###############################################
#calculates angle (vertical, degrees above or below directly
# horizontal) between two geocoords, in degrees
#
var vertAngle_deg = func (geocoord1, geocoord2) {
      var dist=geocoord2.direct_distance_to(geocoord1);
      if ( dist == 0 ) return 0; 
      else return math.asin((geocoord2.alt() - geocoord1.alt())/dist ) * R2D;

}


###############################################
# Checks that the two objects are within the given distance
# and if so, checks whether myNodeName1 is aimed directly at myNodeName2
# within the heading & vertical angle given, OR that the two objects
# have crashed (ie, the position of one is within the damage radius of the other).
# If all that is true, returns number 0-1 telling how close the hit (1 being 
# perfect hit), otherwise 0.
# In case of crash, this crashes both objects. 
# works with AI/MP aircraft AND with the main aircraft, which can 
# use myNodeNameX="" 
# Note: This whole approach won't work too well because the position & 
# orientation properties are updated only 1X per second.
# But who knows--it might be 'good enough' . . .
# 
#     # 
    # Notes on calculating the angular size of the target and being
    # able to tell if the weapon is aimed at the target with sufficient accuracy.    
    # 3 degrees @ 200 meters, 2% damage add maximum.
    # This equates to about a 6 meter damage radius
    # 
    # 2.5, 7.5 equates to an object about 10 ft high and 30 feet wide 
    #     about the dimensions of a Sopwith Camel
    #              
    # formula is tan (angle) = damage radius / distance
    # or angle = atan (damage radius/ distance)
    #  however, for 0<x<1, atan(x) ~= x (x expressed in radians).  
    #  Definitely this is close enough for our purposes.
    # 
    # Since our angles are expressed in degress the only difficulty is to convert radians        
    # to degrees. So the formula is:
    # angle (degrees) = damage radius / distance * (180/pi)
    # 
    # Below we'll put in the general height & width of the object, so the equations become:        
    #
    # # angle (degrees) = height/2 / distance * (180/pi)
    # # angle (degrees) = width/2 / distance * (180/pi)                               
    # (approximate because our damage area is a rectangle projected 
    # onto the surface of a sphere here, not just a radius )
    # Good estimate: dimension in feet divided by 4 equals angle to use here    
    #                      
    # We make the 'hit' area tall & skinny rather than wide & flat 
    # because our fighters are vertically challenged as far as movement,
    #     but quite easily able to aim horizontally
    #
    #Current notes:
    #vertDeg & horzDeg define the angular size of the target (ie, our main aircraft) at
    #the distance of maxDamageDistance_m.  3.43 degrees x 3.43 degrees at 500 meters is approximately right 
    #for (say) a sopwith camel.  Really this needs to be calculated more exactly based on the
    #actual dimensions of the main aircraft. But for now this is at least close.  There doesn't
    #seem to be a simple way to get the dimensions of the main aircraft from FG.
    #Bombable calculates the hits as on a probabalistic basis if they hit within the given
    #angular area.  The closer to the center of the target, the higher the probability of a hit
    #and the more the damage.  Since the bombable/ai weapons system is simulated (ie, based on the probably
    # of hits based on being aimed in the general area of the main aircraft, rather than
    # actually launching projectiles and seeing if they hit) this is generally a 'good enough'
    # approach.       
 

var checkAim = func (myNodeName1="", myNodeName2="",   
          targetSize_m=nil,  aiAimFudgeFactor=1, maxDistance_m=100, weaponAngle_deg=nil, weaponOffset_m=nil, damageValue=0 ) {
          
  #Weapons malfunction in proportion to the damageValue, to 100% of the time when damage=100%
  #debprint ("Bombable: AI weapons, ", myNodeName1);  
  if (rand()<damageValue) return 0 ;
  
  #if (myNodeName1=="/environment" or myNodeName1=="environment") myNodeName1="";
  #if (myNodeName2=="/environment" or myNodeName2=="environment") myNodeName2="";

  #m_per_deg_lat=getprop ("/bombable/sharedconstants/m_per_deg_lat");
  #m_per_deg_lon=getprop ("/bombable/sharedconstants/m_per_deg_lon");

	#quick-n-dirty way to tell if an impact is close to our object at all
  #without processor-intensive calculations
  #we do this first and then exit if not close, to reduce impact
  #of impacts on processing time
  # 

	var alat_deg = getprop(""~myNodeName1~"/position/latitude-deg");
	var alon_deg = getprop(""~myNodeName1~"/position/longitude-deg");
	var mlat_deg = getprop(""~myNodeName2~"/position/latitude-deg");
	var mlon_deg = getprop(""~myNodeName2~"/position/longitude-deg");
    
	deltaLat_deg=mlat_deg - alat_deg;
	if (abs(deltaLat_deg) > maxDistance_m/m_per_deg_lat ) {
      #debprint ("Aim: Not close in lat.");
      return 0; 
  }    

	#var maxLon_deg = getprop (""~myNodeName1~"/bombable/attributes/dimensions/maxLon");
	# 
	var maxLon_deg = attributes[myNodeName1].dimensions.maxLon;  	
	
  deltaLon_deg= mlon_deg - alon_deg ;
	if (abs(deltaLon_deg) > maxDistance_m/m_per_deg_lon )  {
      #debprint ("Aim: Not close in lon.");
      return 0; 
  }

  
  if ( targetSize_m==nil or targetSize_m.horz<=0 or targetSize_m.vert <=0 or maxDistance_m <= 0) return 0;
  
  if (weaponAngle_deg==nil ){ weaponAngle_deg = {heading:0, elevation:0};}
  if (weaponOffset_m==nil ){ weaponOffset_m = {x:0,y:0,z:0}; } 
  
  #we could speed things up a fair bit by calculating this periodically, storing, and 
  # looking up, rather than re-calculating each & every time.  
  #var aLat_rad=alat_deg/rad2degrees;  
  #m_per_deg_lat= 111699.7 - 1132.978 * math.cos (aLat_rad);
  #m_per_deg_lon= 111321.5 * math.cos (aLat_rad);
  

  
  #the following plus deltaAlt_m make a <vector> where impactor is at <0,0,0>
  # and target object is at <deltaX,deltaY,deltaAlt> in relation to it.  
  var deltaY_m=deltaLat_deg*m_per_deg_lat;
  var deltaX_m=deltaLon_deg*m_per_deg_lon;

  var aAlt_m= getprop(""~myNodeName1~"/position/altitude-ft")*feet2meters;
  var mAlt_m= getprop(""~myNodeName2~"/position/altitude-ft")*feet2meters;
  var deltaAlt_m = mAlt_m-aAlt_m;

  distance_m = cartesianDistance (deltaY_m, deltaX_m,deltaAlt_m);
  
  #var geocoord1=any_aircraft_position (myNodeName1);
  #var geocoord2=any_aircraft_position (myNodeName2);
  
  #offset the location of the weapon by the weaponOffset_m amount:
  # Ok, this is slow, we're disabling it for now  
  #var geocoord1 = geocoord1.set_xyz(geocoord1.x()+ weaponOffset_m.x, geocoord1.y()+ weaponOffset_m.y, geocoord1.z()+ weaponOffset_m.z);
   
  #var distance_m = geocoord1.direct_distance_to(geocoord2);
  
  #debprint ("Bombable: AI weapons, distance: ", distance_m);
  
  if (distance_m > maxDistance_m ) return 0;
    # # angle (degrees) = height/2 / distance * (180/pi)
    # # angle (degrees) = width/2 / distance * (180/pi)                               
  

  #collision, ie aircraft 2 within damageRadius of aircraft 1
  if (distance_m < attributes[myNodeName1].dimensions.crashRadius_m){
     #simple way to do this:
     add_damage(1, myNodeName1, "weapon");     
     msg= sprintf("You crashed! Damage added %1.0f%%", 100 );
     selfStatusPopupTip (msg, 10);
     return 1;   
     
     #more complicated way--maybe we'll try it later:
     #case of within vital damage, it's case closed, both aircraft totalled
     var retDam=0;     
     #var vDamRad_m=getprop (""~myNodeName1~"/bombable/attributes/dimensions/vitalDamageRadius_m");
     var vDamRad_m = attributes[myNodeName1].dimensions.vitalDamageRadius_m;
     #var damRad_m=getprop (""~myNodeName1~"/bombable/attributes/dimensions/damageRadius_m");
     var damRad_m = attributes[myNodeName1].dimensions.damageRadius_m;
     if (damRad_m<=0) damRad_m=.5;
     if (vDamRad_m>=damRad_m) vDamRad_m=damRad_m*.95;
     
     if (distance_m < vDamRad_m){
        add_damage(1, myNodeName1, "weapon");
        retDam= 1;
     } else {
     # case of only within damageRadius but not vitalDamageRadius, we'll do as with impact damage
     # and possibly just assess partial damage depending on the distance involved.
       var damPot=(damRad_m-distance_m) / (damRad_m-vDamRad_m); #ranges 0 (fringe) to 1 (at vitalDamageRadius)
       if (rand()< damPot) {
         add_damage(1, myNodeName1, "weapon");
         retDam= 1;
       } else{
          add_damage(rand()*damPot, myNodeName1, "weapon");
          retDam= rand()*damPot;
       }          
     }
     
     msg= sprintf("You crashed! Damage added %1.0f%%", retDam*100 );
     selfStatusPopupTip (msg, 10);
     return retDam;      
  }
  
  #var factor=maxDistance_m/distance_m;#as the object gets closer we can expand the degrees of a hit to be bigger; at maxDistance it is X degrees but if 1/2 maxDistance, 2X degrees, etc
  
  if (myNodeName1=="") myHeading_deg=getprop (""~myNodeName1~"/orientation/heading-deg"); 
  else myHeading_deg=getprop (""~myNodeName1~"/orientation/true-heading-deg");
  
  var headingNode1ToNode2_deg=math.atan2(deltaX_m,deltaY_m) * R2D;
  
  #debprint ("heading1to2: ", headingNode1ToNode2_deg );
  
  var headingDelta_deg=math.abs(normdeg180 ( headingNode1ToNode2_deg -  ( myHeading_deg + weaponAngle_deg.heading) ) );
  
  #debprint( "Bombable: checkAim distance "~ distance_m ~ " heading_delta ", headingDelta_deg);

    # Formula: angle (degrees) = height/2 / distance * (180/pi)
    # # angle (degrees) = width/2 / distance * (180/pi)                               

  var horzTargetSize_deg = targetSize_m.horz/distance_m * (rad2degrees/2) * aiAimFudgeFactor;
  #debprint( "Bombable: checkAim horzTargetSize_deg", horzTargetSize_deg);
  
  if ( headingDelta_deg > horzTargetSize_deg ) return 0;
  
  #fire the weapons for 5 seconds/visual effect
  #we start do this whenever we're within maxDistance & aimed generally at the right heading
  fireAIWeapon(5); 
  
  var myPitch_deg=getprop (""~myNodeName1~"/orientation/pitch-deg");
  
  var pitchNode1toNode2_deg=math.asin(deltaAlt_m/distance_m)*R2D;
  
  #debprint ("pitch1to2: ", pitchNode1toNode2_deg);
    
  #var vertDelta_deg= math.abs ( normdeg180 (vertAngle_deg(geocoord1,geocoord2) - ( myPitch_deg + weaponAngle_deg.elevation ) ) );
  
  var vertDelta_deg= math.abs ( normdeg180 (pitchNode1toNode2_deg - ( myPitch_deg + weaponAngle_deg.elevation ) ) );
   
   
        
  
  #extra fudgefactor on vert because our fighters are a bit vertically-aiming challenged  
  var vertTargetSize_deg = targetSize_m.vert/distance_m * (rad2degrees/2) * aiAimFudgeFactor * 1.5;

  #debprint( "Bombable: checkAim vertDelta ", vertDelta_deg, " vertTargetSize_deg ", vertTargetSize_deg );
    
  if ( vertDelta_deg  > vertTargetSize_deg ) return 0;
    
  var result = (1 - vertDelta_deg/vertTargetSize_deg) * (  1 - headingDelta_deg/horzTargetSize_deg);
  
  return result;  #ranges 0 to 1, 1 being direct hit
  
} 

#########################################################
# weapons_loop - main timer loop for check AI weapon aim & damae
# to main aircraft
# 
# Todo: We could check how often this loop is being called (by all AI objects
# in total) and if it is being called too often, exit.  This can have a 
# bad effect on the framerate if the main aircraft gets into a crowd
# of AI objects.
# 
# We could implement an approach to finding distance/direction more like the one
# in test_impact, where we just use an local coordinate system of lat/lon/eleve
# to calculate target distance. That seems far more frugal of CPU time than 
# geoCoord and directdistanceto, which both seem quite expensive of CPU.   
    
var weapons_loop = func (id, myNodeName1="", myNodeName2="", targetSize_m=nil) {

   #we increment loopid if we want to kill this timer loop.  So check if we need to kill/exit:
   # myNodeName1 is the AI aircraft and nyNodeName2 is the main aircraft    
   var loopid = getprop(""~myNodeName1~"/bombable/loopids/weapons-loopid"); 
   id == loopid or return;
   #debprint ("aim-timer");
   
   var loopLength=.5; 
   settimer (  func { weapons_loop (id, myNodeName1, myNodeName2, targetSize_m )}, loopLength * (1 + rand()/8));

   #debprint ("weapons_loop starting");

   if (! getprop ( bomb_menu_pp~"ai-aircraft-weapons-enabled") or ! getprop(bomb_menu_pp~"bombable-enabled") ) return;
   
   

   #if no weapons set up for this Object then just return
   if (! getprop(""~myNodeName1~"/bombable/initializers/weapons-initialized")) return;
      
   #var b = props.globals.getNode (""~myNodeName1~"/bombable/attributes");
   var weaps= attributes[myNodeName1].weapons;
   #debprint ("aim-check damage");
   #If damage = 100% we're going to assume the weapons won't work.
   var damageValue = getprop(""~myNodeName1~"/bombable/attributes/damage");
   if (damageValue==1) return;  
   
   aiAimFudgeFactor= getprop (""~bomb_menu_pp~"ai-weapon-power");
   if (aiAimFudgeFactor==nil or aiAimFudgeFactor==0) aiAimFudgeFactor=11.5;
   
   #pilotSkill varies -1 to 1, 0= average
   var pilotSkill = getprop(""~myNodeName1~"/bombable/weapons-pilot-ability");
	 if (pilotSkill==nil) pilotSkill=0;
	 
	 aiAimFudgeFactor+=  pilotSkill*9;
	 if (aiAimFudgeFactor<0) aiAimFudgeFactor=0;
	 
 
   
   #debprint ("aim-each weapon");                       
   foreach (elem;keys (weaps) ) {

       #   elem.maxDamageDistance_m, 
       #           elem.maxDamage_percent, elem.weaponAngle_deg, 
       #           elem.weaponOffset_m
       # 
       # 
       #               
     mDD_m = weaps[elem].maxDamageDistance_m;
     if (mDD_m==nil or mDD_m==0) mDD_m=100;       
     #debprint ("Bombable: Weapons_loop ", myNodeName1, " ", weaps[elem].maxDamageDistance_m);

     #can't shoot if no ammo left!
     if ( ! stores.checkWeaponsReadiness ( myNodeName1, elem ) ) continue; 

  
     result=checkAim (myNodeName1, myNodeName2, targetSize_m, aiAimFudgeFactor,  
                 weaps[elem].maxDamageDistance_m, weaps[elem].weaponAngle_deg, 
                 weaps[elem].weaponOffset_m, damageValue );
     
     #debprint ("aim-check weapon"); 
     if (result==0) continue;
     
     debprint ("Bombable: AI aircraft aimed at main aircraft, ",
        myNodeName1, " ", weaps[elem].name, " ", elem, 
        " accuracy ", round(result * 100 ),"%");

     

     #reduce ammo count; bad pilots waste more ammo; pilotskill ranges -1 to 1
     stores.reduceWeaponsCount (myNodeName1,elem,loopLength*(3-pilotSkill));     

   
     # As with our regular damage, it has a result% change of registering
     # a hit and then the damage amount is higher as result increases, too.    
     # There is a smaller chance of doing a fairly high level of damage (up to 3X the regular max), 
     # and the better/closer the hit, the greater chance of doing that significant damage.  
     var r=rand();    
     if (r < result) {

         var ai_callsign = getCallSign (myNodeName1);
               
         var damageAdd= result * weaps[elem].maxDamage_percent/100;
           
         #Some chance of doing more damage (and a higher chance the closer the hit)
         if (r < result/5 ) damageAdd *= 3*rand();
           
         weaponName=weaps[elem].name;
         if (weaponName==nil) weaponName="Main Weapon"; 
           
         mainAC_add_damage ( damageAdd, 0, "weapons", 
              "Hit from " ~ ai_callsign ~ " - " ~ weaponName ~"!");
     
     }
  }   
} 

##########################################################
# CLASS stores
# singleton class to hold methods for filling, depleting,
# checking AI aircraft stores, like fuel & weapon rounds
# 
var stores={};

##########################################################
# FUNCTION reduceWeaponsCount
# As the weapons are fired, reduce the count in the AC's stores
# 
stores.reduceWeaponsCount = func (myNodeName, elem, time_sec) {

  var stos = attributes[myNodeName].stores;  
  var ammo_seconds=60;  #Number of seconds worth of ammo firing the weapon has
                        #TODO: This should be set per aircraft per weapon
  if (stos["weapons"][elem]==nil) stos["weapons"][elem] = 0; 
  stos.weapons[elem] -= time_sec/ammo_seconds; 
  if (stos.weapons[elem] < 0 ) stos.weapons[elem] = 0; 
}


##########################################################
# FUNCTION reduceFuel
# As the AC attacks, reduce the amount of fuel in the stores
# For now we are just going for amount of time allowed for combat
# since typically fuel use in much higher in that situation.
# TODO: Also account for fuel use while patrolling etc.
# 
stores.reduceFuel = func (myNodeName, time_sec) {

  var stos = attributes[myNodeName].stores;  
  var fuel_seconds=600;  #Number of seconds worth of combat time the AC has in
                         #fuel reserves.
                         #TODO: This should be set per aircraft
  if (stos["fuel"]==nil) stos["fuel"]=0; 
  stos.fuel -= time_sec/fuel_seconds; 
  if (stos.fuel < 0 ) stos.fuel=0;
}

###############################################
# FUNCTION fillFuel
# 
# fuel is the amount of reserves remaining to carry
# out maneuvers & attacks, not the total fuel 
# 
#
stores.fillFuel = func (myNodeName,amount=1){

  if ( ! contains ( attributes, myNodeName) or 
       ! contains ( attributes[myNodeName], "stores") ) return;
        
  var stos= attributes[myNodeName].stores;
  debprint ("Bombable: Filling fuel for", myNodeName); 
  if (stos["fuel"]==nil) stos["fuel"] = 0;
  stos["fuel"]+= amount;
  if (stos["fuel"] > 1 ) stos["fuel"]=1;
}

###############################################
# FUNCTION fillWeapons
# 
#
stores.fillWeapons = func (myNodeName, amount=1){

  if ( ! contains ( attributes, myNodeName) or 
       ! contains ( attributes[myNodeName], "stores") ) return;

 var weaps = attributes[myNodeName].weapons;
 var stos = attributes[myNodeName].stores; 
 
 debprint ("Bombable: Filling weapons for", myNodeName);  
 foreach (elem;keys (weaps) ) {
  if (stos["weapons"][elem]==nil) stos["weapons"][elem]=0; 
  stos["weapons"][elem]+= amount;
  if (stos["weapons"][elem] > 1 ) stos["weapons"][elem]=1;
 } 
}

###############################################
# FUNCTION repairDamage
# 
# removes amount from damage
#
stores.repairDamage = func (myNodeName, amount=0 ){
  var damage=getprop("" ~ myNodeName ~ "/bombable/attributes/damage");
  if (damage==nil) damage=0;
  damage -= amount;
  if (damage>1) damage = 1;
  if (damage<0) damage = 0;
  setprop("" ~ myNodeName~"/bombable/attributes/damage", damage);
  
}

###############################################
# FUNCTION checkWeaponsReadiness
# 
# checks if a weapon or all weapons has ammo or not.  returns 1 if ammo, 0
# otherwise.  If elem is given, checks that single weapon, otherwise checks
# all weapons for that object.  Returns 1 if at least one weapon still has
# ammo 
# 
stores.checkWeaponsReadiness = func (myNodeName, elem=nil) {
  var stos = attributes[myNodeName].stores;
  
  if (elem != nil ) {
    if (stos.weapons[elem]!=nil and stos.weapons[elem] == 0 ) return 0;
    else return 1;
  } else {
      foreach (elem;keys (stos.weapons) ) {
        if (stos.weapons[elem]!=nil and stos.weapons[elem] > 0 ) return 1;
      }
      return 0;
  }     
}

###############################################
# FUNCTION fuelLevel
# 
# checks fuel level
# fuel is the amount of reserves remaining to carry
# out maneuvers & attacks, not the total fuel 
# 
stores.fuelLevel = func (myNodeName) {
  var stos = attributes[myNodeName].stores;
  
  if (stos.fuel!=nil) return stos.fuel;
  else return 0;   

}

###############################################
# FUNCTION checkAttackReadiness
# 
# checks weapons, fuel, damage level, etc, to see if an AI
# should continue to attack or not
# 
stores.checkAttackReadiness = func (myNodeName) {
  var ret=1;
  var msg="Bombable: CheckAttackReadiness for  " ~ myNodeName;
  var stos= attributes[myNodeName].stores;
  var weaps = attributes[myNodeName].weapons;
 
  if (stos["fuel"]!=nil and stos.fuel < .2) ret=0;
  msg~=" fuel:"~ stos.fuel;
  var damage=getprop("" ~ myNodeName ~ "/bombable/attributes/damage");
  if (damage!=nil and damage > .8) ret=0;
  msg~=" damage:"~ damage;
  
  #for weapons, if at least 1 weapon has at least 10% ammo we 
  # will continue to attack  
  weapret=0;
  foreach (elem;keys (weaps) ) {
      if (stos.weapons[elem]!=nil and stos.weapons[elem] > .2 ) weapret=1;
      msg~=" "~elem~" "~ stos.weapons[elem];
  }
  if (! weapret) ret=0;
  debprint (msg, " Readiness: ", ret);
  if (ret == 0 and ! stos["messages"]["unreadymessageposted"] ) {
    var callsign=getCallSign(myNodeName);
    var popmsg= callsign ~ " is low on weapons/fuel";
    targetStatusPopupTip (popmsg, 10);
    stos["messages"]["unreadymessageposted"]=1;
    stos["messages"]["readymessageposted"]=0;

  }  
  return ret;
}

###############################################
# FUNCTION revitalizeAttackReadiness
# 
# After the aircraft has left the attack zone it 
# can start to refill weapons, fuel, repair damage etc.
# This function takes care of all that.
# 
#
stores.revitalizeAttackReadiness = func (myNodeName,dist_m=1000000){

  var atts= attributes[myNodeName].attacks;
  var stos= attributes[myNodeName].stores;
  
  #We'll say if the object is > .9X the minimum attack
  # distance it can refuel, refill weapons, start to repair
  # damage.    
  if (dist_m > atts.maxDistance_m * .9 ) {
      me.fillFuel (myNodeName, 1);
      me.fillWeapons (myNodeName, 1);
      me.repairDamage (myNodeName, .01);
      deleteFire(myNodeName);
      if (getprop(""~myNodeName~"/bombable/attributes/damage")<.25) deleteSmoke("damagedengine", myNodeName);
      
      if (! stos["messages"]["readymessageposted"] ) {
        var callsign=getCallSign(myNodeName);
        var popmsg = callsign ~ " has reloaded weapons, fuel, and repaired damage";
        targetStatusPopupTip (popmsg, 10);
        stos["messages"]["unreadymessageposted"]=0;
        stos["messages"]["readymessageposted"]=1;
      }  
      debprint ("Bombable: Revitalizing attack readiness for ", myNodeName);
  }
  
}

#END CLASS stores
###############################################
 

###############################################
#returns myNodeName position as a geo.Coord
# works for any aircraft; for main aircraft myNodeName="" 
var any_aircraft_position = func (myNodeName) {
  #if (myNodeName=="/environment" or myNodeName=="environment") myNodeName="";
  
  #if (myNodeName=="") debprint ("Bombable: Updating main aircraft 2700");
  
	var lat = getprop(""~myNodeName~"/position/latitude-deg");
	var lon = getprop(""~myNodeName~"/position/longitude-deg");
	var alt = getprop(""~myNodeName~"/position/altitude-ft") * FT2M;
	return geo.Coord.new().set_latlon(lat, lon, alt);
}

####################################################
#returns vector [direct distance (m), altitude difference (m)] 
# from main aircraft to myNodeName
var distAItoMainAircraft= func (myNodeName){
   mainAircraftPosition=geo.aircraft_position();
   aiAircraftPosition=any_aircraft_position(myNodeName);
   
   return [ aiAircraftPosition.direct_distance_to(mainAircraftPosition),
         aiAircraftPosition.alt() - mainAircraftPosition.alt() ];
}

####################################################
#returns course from myNodeName to main aircraft 
#
var courseToMainAircraft = func (myNodeName){
   mainAircraftPosition=geo.aircraft_position();
   aiAircraftPosition=any_aircraft_position(myNodeName);
   
   return aiAircraftPosition.course_to(mainAircraftPosition);
}

####################################################
#attack_loop
# Main loop for calculating attacks, changing direction, altitude, etc. 
#

var attack_loop = func (id, myNodeName, looptime) {
  
  var loopid = getprop(""~myNodeName~"/bombable/loopids/attack-loopid"); 
	id == loopid or return;
	
	#debprint ("attack_loop starting");
	
  looptimealt = getprop(""~myNodeName~"/bombable/attack-looptime");
  if (looptimealt!=nil and looptimealt > 0) looptime = looptimealt;
  setprop(""~myNodeName~"/bombable/attack-looptime", looptime); 
	
	#skill ranges 0-5; 0=disabled, so 1-5;
  var skill = calcPilotSkill (myNodeName);	
  if (skill<=.2) skillMult=3/0.2;
  else skillMult= 3/skill;
	
  #Higher skill makes the AI pilot react faster/more often:
  var looptimeActual=skillMult*looptime;  
  settimer ( func { attack_loop (id, myNodeName, looptime) }, looptimeActual);
  
  #we're going to say that dodging takes priority over attacking
  if (getprop ( ""~myNodeName~"/bombable/dodge-inprogress")) return;
  
	
  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  var atts= attributes[myNodeName].attacks;
  var alts= attributes[myNodeName].altitudes;
  
	if (  ! getprop (bomb_menu_pp~"ai-aircraft-attack-enabled") or ! getprop(bomb_menu_pp~"bombable-enabled") or getprop("" ~ myNodeName~"/bombable/attributes/damage")==1 ) {
     setprop(""~myNodeName~"/bombable/attack-looptime", atts.attackCheckTime_sec);
     return;
  }          
  
  
  var dist =  distAItoMainAircraft (myNodeName);
  var courseToTarget_deg=courseToMainAircraft(myNodeName);
  #debprint ("Bombable: Checking attack parameters: ", dist[0], " ", atts.maxDistance_m, " ",atts.minDistance_m, " ",dist[1], " ",-atts.altitudeLowerCutoff_m, " ",dist[1] < atts.altitudeHigherCutoff_m );
  
  
  var myHeading_deg=getprop (""~myNodeName~"/orientation/true-heading-deg");
  var deltaHeading_deg=myHeading_deg - courseToTarget_deg;                    
  deltaHeading_deg = math.mod (deltaHeading_deg + 180, 360) - 180;   
  var targetHeading_deg= getprop("/orientation/heading-deg");   
  
  #whether or not to continue the attack when within minDistance
  #If we are headed basically straight towards the Target aircraft 
  # we continue (within continueAttackAngle_deg of straight on)
  # or if we are still quite a ways above or below the main AC,
  # we continue the attack    
  # otherwise we break off the attack/evade      
  var continueAttack=0;
  if ( dist[0] < atts.minDistance_m ) {
  
    var newAltLowerCutoff_m = atts.altitudeLowerCutoff_m/4;
    if (newAltLowerCutoff_m < 150) newAltLowerCutoff_m = 200; 
    var newAltHigherCutoff_m = atts.altitudeHigherCutoff_m/4;
    if (newAltHigherCutoff_m < 150) newAltHigherCutoff_m = 200;     
 
    if (math.abs ( deltaHeading_deg ) < atts.continueAttackAngle_deg  
       or dist[1] < -newAltLowerCutoff_m or dist[1] > newAltHigherCutoff_m ) continueAttack=1;
     
  }
  
  #readiness=0 means it has little fuel/weapons left.  It will cease
  # attacking UNLESS the main AC comes very close by & attacks it.
  # However there is no point in attacking if no ammo at all, in that 
  # case only dodging/evading will happen.  
  var readinessAttack=1;
  if ( ! stores.checkAttackReadiness(myNodeName) ) {
     
     var newMaxDist_m=atts.maxDistance_m/8;
     if (newMaxDist_m<atts.minDistance_m) newMaxDist_m=atts.minDistance_m*1.5;
      
     readinessAttack= dist[0] < newMaxDist_m and ( dist[0] > atts.minDistance_m or continueAttack ) and dist[1] > -atts.altitudeLowerCutoff_m/3 and dist[1] < atts.altitudeHigherCutoff_m/3 and stores.checkWeaponsReadiness(myNodeName);
  } 
  
  #OK, we spend 13% of our time zoning out.  http://discovermagazine.com/2009/jul-aug/15-brain-stop-paying-attention-zoning-out-crucial-mental-state
  # Or maybe we are distracted by some other task or whatever.  At any rate,
  # this is a human factor for the possibility that they could have observed/
  # attacked in this situation, but didn't.  We'll assume more skilled
  # pilots are more observant and less distracted.  We'll assume 13% of the time
  # is the average.
  # Attention is presumably much higher during an attack but since this loop
  # runs much more often during an attack that should cancel out.  Plus there
  # might be other distractions during an attack, even if not so much 
  # daydreaming.   
  # This only applies to the start of an attack.  Once attacking, presumably 
  # we are paying enough attention to continue.                
  var attentionFactor=1;     
  if (rand()< .20 - 2*skill/100) attentionFactor=0;
  
  # The further away we are, the less likely to notice the MainAC and start
  # an attack.  
  # This only applies to the start of an attack.  Once attacking, presumably 
  # we are paying enough attention to continue.
  var distanceFactor=1;
  if (rand()<dist[0]/atts.maxDistance_m) distanceFactor=0;
  if (dist[1]<0) if  (rand() < -dist[1]/atts.altitudeLowerCutoff_m)  distanceFactor=0; 
  elsif (rand() < dist[1]/atts.altitudeHigherCutoff_m)  distanceFactor=0;    
  
  #TODO: Other factors could be added here, like less likely to attack if
  #    behind a cloud, more likely if rest of squadron is, etc.
  
  var attack_inprogress=getprop(""~myNodeName~"/bombable/attack-inprogress");
    
  #criteria for attacking (or more precisely, for not attacking) . . . if 
  # we meet any of these criteria we do a few things then exit without attacking  
  if ( ! (dist[0] < atts.maxDistance_m and ( dist[0] > atts.minDistance_m or continueAttack ) and dist[1] > -atts.altitudeLowerCutoff_m and dist[1] < atts.altitudeHigherCutoff_m  and  readinessAttack and ( (attentionFactor and distanceFactor) or attack_inprogress ) ) )  {
     
    #OK, no attack, we're too far away or too close & passed it, too low, too high, etc etc etc
    #Instead we: 1. dodge if necessary 2. exit 
    #always dodge when close to Target aircraft--unless we're aiming at it
    #ie, after passing it by, we make a dodge.  Less skilled pilots dodge less often.
        
    # When the AC is done attacking & dodging it will continue to fly in 
    # circles unless we do this    
    setprop (""~myNodeName~"/controls/flight/target-roll", rand()*2-1);  
    
    #If not attacking, every once in a while we turn the AI AC in the general 
    #direction of the Main AC
    #This is to keep the AC from getting too dispersed all over the place.
    #TODO: We could do lots of things here, like have the AC join up in squadrons,
    #return to a certain staging area, patrol a certain area, or whatever.    
    if (rand()< .03 and atts.maxDistance_m) {
     aircraftTurnToHeading ( myNodeName, courseToTarget_deg, 60);
     debprint ("Bombable: Not attacking, turning in general direction of main AC");
    } 

    #are we ahead of or behind the target AC?  If behind, there is little point
    # in dodging.  aheadBehindTarget_deg will be 0 degrees if we're directly 
    # behind, 90 deg
    # if directly to the side.  We dodge only if >110 degrees, which puts 
    # us pretty much in frontish.      
    var aheadBehindTarget_deg=normdeg180 (targetHeading_deg - courseToTarget_deg);     
    
    if (dist[0] < atts.minDistance_m and rand() < skill/5 and math.abs(aheadBehindTarget_deg) > 110)  dodge( myNodeName);
    
    if ( dist[0] > atts.maxDistance_m ) stores.revitalizeAttackReadiness(myNodeName, dist[0]);
    
    setprop(""~myNodeName~"/bombable/attack-looptime", atts.attackCheckTime_sec);
    setprop(""~myNodeName~"/bombable/attack-inprogress", "0"); 
    return;
  }
      
  stores.reduceFuel (myNodeName, looptimeActual ); #deduct the amount of fuel from the tank
  
  #attack
  #   
  #debprint ("Bombable: Starting attack run of Target aircraft with " ~ myNodeName );
  # (1-rand()*rand()) makes it choose values at the higher end of the range more often    
  
  var roll_deg= (1-rand()*rand()) * (atts.rollMax_deg-atts.rollMin_deg) + atts.rollMin_deg;
  
  #debprint ("rolldeg:", roll_deg);
  
  #if we are aiming almost at our target we reduce the roll if we are 
  #close to aiming at them
  if (math.abs(roll_deg) > 4 * math.abs(deltaHeading_deg)){
    roll_deg = 4 * math.abs(deltaHeading_deg); 
  }
  
  
  
  #var aiAircraftPosition = any_aircraft_position(myNodeName);
  
  var targetAlt_m=geo.aircraft_position().alt();
  attackCheckTimeEngaged_sec=atts.attackCheckTimeEngaged_sec;
  
  #Easy mode makes the attack manuevers less aggressive
  #if (skill==2) roll_deg*=0.9; 
  #if (skill==1) roll_deg*=0.8; 
  
  #reduce the roll according to skill
  roll_deg*=(skill+6)/12;
  
    #debprint ("rolldeg:", roll_deg);
           
  courseToTarget_deg += (rand()*16-8) * skillMult; #keeps the moves from being so robotic and makes the lower skilled AI pilots less able to aim for the Target aircraft

  #it turns out that the main AC's AGL is available in the prop tree, which is
  #far quicker to access then the elev function, which is very slow
  #elevTarget_m = elev (geo.aircraft_position().lat(),geo.aircraft_position().lon() )*feet2meters;
  #targetAGL_m=targetAlt_m-elevTarget_m;
  
  targetAGL_m = getprop ("/position/altitude-agl-ft") * feet2meters;
  elevTarget_m =targetAlt_m-targetAGL_m;
  currAlt_m = getprop(""~myNodeName~"/position/altitude-ft")*feet2meters;


  var attackClimbDive_inprogress=getprop(""~myNodeName~"/bombable/attackClimbDive-inprogress");
  var attackClimbDive_targetAGL_m=getprop(""~myNodeName~"/bombable/attackClimbDive-targetAGL_m"); 
  
  setprop(""~myNodeName~"/bombable/attack-inprogress", "1");

  # is this the start of our attack?  If so or if we're heading away from the   
  # target, we'll possibly do a loop or strong altitude move 
  # to get turned around, and continue that until we are close than 90 degrees
  # in heading delta                     
  if ((attack_inprogress== nil or attack_inprogress==0) or (math.abs ( deltaHeading_deg ) >= 90) ) {
    
    
    
    #if we've already started an attack loop, keep doing it with the same 
    #  targetAGL, unless we have arrived within 500 meters of that elevation 
    #  already.  Also we randomly pick a new targetaltitude every so often
    if (attackClimbDive_inprogress and 
         ( attackClimbDive_targetAGL_m != nil and attackClimbDive_targetAGL_m > 0                    
           and math.abs(attackClimbDive_targetAGL_m + elevTarget_m - currAlt_m) > 500 
           and (rand()> 0.005 * skill)
           ) ) {
            
            targetAGL_m = attackClimbDive_targetAGL_m; 
            
    } else {
      #otherwise, we are starting a new attack so we need to figure out what to do
    
    

      #if we're skilled and we have enough speed we'll do a loop to get in better position  
      #more skilled pilots do acrobatics more often
      # in the Zero 130 kt is about the minimum speed needed to 
      # complete a loop without stalling.  
      # TODO: This varies by AC.  As a first try we're going with 2X
      # minSpeed_kt to complete the loop.      
      #       
      vels= attributes[myNodeName].velocities;      
      var currSpeed_kt=getprop (""~myNodeName~"/velocities/true-airspeed-kt");                    
      if (currSpeed_kt>2.2*vels.minSpeed_kt and rand() < (skill+8)/15) {
         if ( choose_attack_acrobatic(myNodeName, dist[0], myHeading_deg, 
              targetHeading_deg, courseToTarget_deg, deltaHeading_deg, 
              currSpeed_kt, skill, currAlt_m, targetAlt_m, elevTarget_m))
            return;
       }
 
               
  
  
     
     #we want to mostly dodge to upper/lower extremes of our altitude limits   
     var attackClimbDiveAddFact=1-rand()*rand()*rand();
     #worse pilots don't dodge as far
     attackClimbDiveAddFact*=(skill+3)/9;
     #the direction of the Alt dodge will favor the direction that has more
     # feet to dodge in the evasions definitions.  Some aircraft heavily favor
     # diving to escape, for instance.      
     # 
      
     #climb or dive more according to the aircraft's capabilities.  
     # However note that by itself this will lead the AI AC to climb/dive 
     # away from the Target AC unless climbPower & divePower are equal.  So we 
     # mediate this by adjusting if it gets too far above/below the Target AC
     # altitude (see below))                                                   
     var attackClimbDiveAddDirection=rand() * (atts.climbPower + atts.divePower) - atts.divePower;
     
     # for this purpose we use 50/50 climbs & dives because using a different     
     # proportion tends to put the aircraft way above or below the Target aircraft
     # over time, by a larger amount than they can correct in the reTargeting
     # part of their attack pattern.  
     #var attackClimbDiveAddDirection=2*rand()-1;     
 
     
     #if we're too high or too low compared with Target AC then we'll climb or 
     #    dive towards it always.  This prevents aircraft from accidentally 
     #    climbing/diving away from the Target AC too much.
     deltaAlt_m=currAlt_m-targetAlt_m;
     if (deltaAlt_m>0) {
        if ( deltaAlt_m > atts.divePower/6 ) attackClimbDiveAddDirection = -1; 
     } else {
        if ( -deltaAlt_m > atts.climbPower/6 ) attackClimbDiveAddDirection = 1;
     }
     
     #           #for FG's AI to make a good dive/climb the difference in altitude must be at least 5000 ft
     
     #target amount to climb or drop
     if (attackClimbDiveAddDirection>=0)  
         attackClimbDiveAdd_m=attackClimbDiveAddFact*atts.climbPower;
     else     
         attackClimbDiveAdd_m=-attackClimbDiveAddFact*atts.divePower;
                                                                                
  
  
        #attackClimbDiveAdd_m = rand() * (atts.climbPower + atts.divePower) - atts.divePower;  #for FG's AI to make a good dive/climb the difference in altitude must be at least 5000 ft
        
        
        targetAGL_m = currAlt_m + attackClimbDiveAdd_m - elevTarget_m;
        
        
        if (targetAGL_m < alts.minimumAGL_m) targetAGL_m = alts.minimumAGL_m;
        if (targetAGL_m > alts.maximumAGL_m) targetAGL_m = alts.maximumAGL_m;
        
        #debprint ("Bombable: Starting attack turn/loop for ", myNodeName," targetAGL_m=", targetAGL_m);
        setprop(""~myNodeName~"/bombable/attackClimbDive-inprogress", "1");  
        setprop(""~myNodeName~"/bombable/attackClimbDive-targetAGL_m", targetAGL_m); 
   }  
      
  } else {
    setprop(""~myNodeName~"/bombable/attackClimbDive-inprogress", "0");
    #debprint ("Bombable: Ending attack turn/loop for ", myNodeName);       
  }
  
  targetAlt_m= targetAGL_m + elevTarget_m;                                       
  
  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  var alts = attributes[myNodeName].altitudes;
  if (targetAGL_m < alts.minimumAGL_m ) targetAGL_m = alts.minimumAGL_m;
  if (targetAGL_m > alts.maximumAGL_m ) targetAGL_m = alts.maximumAGL_m;
  
  #sometimes when the deltaheading is near 180 degrees we turn the opposite way of normal
  #   
  # 
  var favor=getprop(""~myNodeName~"/bombable/favor-direction");
  if ((favor!="normal" and favor !="opposite") or rand()<.003) {    
    var favor="normal"; if (rand()>.5) favor="opposite";
    setprop(""~myNodeName~"/bombable/favor-direction", favor);
  }  
  
  aircraftSetVertSpeed (myNodeName, targetAlt_m - currAlt_m, "evas" );
  
  #debprint ("Bombable: setprop 4275");
  setprop(""~myNodeName~"/bombable/attributes/altitudes/targetAGL_ft", targetAGL_m/feet2meters);
  setprop(""~myNodeName~"/bombable/attributes/altitudes/targetAGL_m", targetAGL_m);
  aircraftTurnToHeading ( myNodeName, courseToTarget_deg, roll_deg, targetAlt_m, atts.rollMax_deg, favor);
  
  
  #update more frequently when engaged with the main aircraft
  setprop(""~myNodeName~"/bombable/attack-looptime", attackCheckTimeEngaged_sec);
  
  
}  
  
  

######################################################
# make an aircraft turn to a certain heading
# older/nonworking version
var aircraftTurnToHeadingOld = func (myNodeName, heading_deg=0, roll_deg=30, turntime=15){
   if (turntime <= 0) turntime=1;
   start_heading_deg=getprop (""~myNodeName~"/orientation/true-heading-deg");
   diff_heading_deg = heading_deg-start_heading_deg;
   while ( diff_heading_deg < 0 ) diff_heading_deg += 360;
   if (diff_heading_deg>180) diff_heading_deg += - 360;
   
   roll_deg=math.sgn (diff_heading_deg)*math.abs(roll_deg);
   
   aircraftRoll(myNodeName,roll_deg,turntime/3);
   settimer (func {
        firstturn_heading_deg=getprop (""~myNodeName~"/orientation/true-heading-deg"); 
        turnamount_deg=firstturn_heading_deg-start_heading_deg;
        while ( turnamount_deg < 0 ) turnamount_deg += 360;
        turnrate_degps=turnamount_deg/turntime*3;
        
        remaining_deg=diff_heading_deg - 2*turnamount_deg;
        if (remaining_deg >= turnrate_degps*turntime/3 ) {
           waittime=remaining_deg/turnrate_degps;
           #hold the roll amount
           aircraftRoll(myNodeName,0,waittime);
           settimer (func { aircraftRoll (myNodeName, -roll_deg, turntime/3)},    
              waittime);
           
        } else {
           roll_deg=math.sgn(remaining_deg)*roll_deg;
           remainingturntime=remaining_deg/turnrate_degps;
           aircraftRoll (myNodeName, roll_deg, remainingturntime)
        
        }
        
      
      }, turntime/3);
      


}

var aircraftSetVertSpeed = func (myNodeName, dodgeAltAmount_ft, evasORatts="evas") {

       var vels = attributes[myNodeName].velocities; 
       var evas = attributes[myNodeName].evasions;
       
       var divAmt=8;
       if (evasORatts=="atts") divAmt=4; 
        
       var dodgeVertSpeed_fps = 0;
       if ( dodgeAltAmount_ft > 150 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps );
       elsif ( dodgeAltAmount_ft > 100 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps/divAmt*4 );
       elsif ( dodgeAltAmount_ft > 75 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps/divAmt*3 );
       elsif ( dodgeAltAmount_ft > 50 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps/divAmt*2 ); 
       elsif ( dodgeAltAmount_ft > 25 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps/divAmt );
       elsif ( dodgeAltAmount_ft > 12.5 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps/divAmt/2 );
       elsif ( dodgeAltAmount_ft > 6 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps/divAmt/3 );
       elsif ( dodgeAltAmount_ft > 0 )  dodgeVertSpeed_fps = math.abs ( evas.dodgeVertSpeedClimb_fps/divAmt/5 );
       elsif  ( dodgeAltAmount_ft < -150 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps);
       elsif  ( dodgeAltAmount_ft < -100 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps/divAmt*4);
       elsif  ( dodgeAltAmount_ft < -75 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps/divAmt*3);
       elsif  ( dodgeAltAmount_ft < -50 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps/divAmt*2);
       elsif  ( dodgeAltAmount_ft < -25 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps/divAmt);
       elsif  ( dodgeAltAmount_ft < -12.5 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps/divAmt/2);
       elsif  ( dodgeAltAmount_ft < -6 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps/divAmt/3);
       elsif  ( dodgeAltAmount_ft < 0 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps/divAmt/5);
       
       #for evasions, the size & speed of the vertical dive is proportional
       # to the amount of dodgeAlt selected.  For atts & climbs it makes more
       # sense to just do max climb/dive until close to the target alt               
       if (evasORatts=="evas") {
          if ( dodgeAltAmount_ft < 0 )  dodgeVertSpeed_fps = - math.abs ( evas.dodgeVertSpeedDive_fps * dodgeAltAmount_ft/evas.dodgeAltMin_ft );
       }    
                                                                      
       
       # If we want a change in vertical speed then we are going to change /velocities/vertical-speed-fps
       # directly.  But by a max of 25 FPS at a time, otherwise it is too abrupt. 
       if (dodgeVertSpeed_fps!=0){
       
          #proportion the amount of vertical speed possible by our current speed
          # stops unreasonably large vertical speeds from happening          
          dodgeVertSpeed_fps*=(getprop(""~myNodeName~"/velocities/true-airspeed-kt")-vels.minSpeed_kt)/(vels.maxSpeed_kt-vels.minSpeed_kt);
          var curr_vertical_speed_fps= getprop ("" ~ myNodeName ~ "/velocities/vertical-speed-fps"); 
          vertSpeedChange_fps=dodgeVertSpeed_fps-curr_vertical_speed_fps;
          if (vertSpeedChange_fps>25) vertSpeedChange_fps=25;
          if (vertSpeedChange_fps<-25) vertSpeedChange_fps=-25;
          var stalling=getprop ("" ~ myNodeName ~ "/bombable/stalling");
          
          #don't do this if we are stalling, except if it makes us fall faster 
          if (!stalling or vertSpeedChange_fps<0) setprop ("" ~ myNodeName ~ "/velocities/vertical-speed-fps", curr_vertical_speed_fps + vertSpeedChange_fps);
          #debprint ("VertSpdChange: ", myNodeName, dodgeAltAmount_ft, dodgeVertSpeed_fps, "vertspeedchange:", vertSpeedChange_fps);
       }

}

##############################;########
# internal - for making AI aircraft turn to certain heading
var aircraftTurnToHeadingControl = func (myNodeName, id, targetdegrees=0, rolldegrees=45, targetAlt_m="none" ,  roll_limit_deg=85, correction=0 ) {
  
  var loopid = getprop(""~myNodeName~"/bombable/loopids/roll-loopid"); 
	id == loopid or return;

  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
  
  targetdegrees=normdeg180(targetdegrees);
  rolldegrees=normdeg180(rolldegrees);
	
	#roll_limit_deg=75; #if more than this FG AI goes a bit wacky; this is 75-80-85, degrees,
	# depend on the aircraft/speed/etc so we let the individual aircraft set it individually	
	if (math.abs(rolldegrees)>roll_limit_deg) rolldegrees=roll_limit_deg*math.sgn(rolldegrees);
  
  
  
   start_heading_deg=getprop (""~myNodeName~"/orientation/true-heading-deg");
   delta_heading_deg = targetdegrees-start_heading_deg;
   while ( delta_heading_deg < 0 ) delta_heading_deg += 360;
   if (delta_heading_deg>180) delta_heading_deg += - 360;
   
   rolldegrees=math.sgn (delta_heading_deg)*math.abs(rolldegrees);
   
   
  
  updateinterval_sec=.1;
  maxTurnTime=60; #max time to stay in this loop/a failsafe
  
  var rollTimeElapsed=getprop(""~myNodeName~ "/orientation/rollTimeElapsed");
  if (rollTimeElapsed==nil) rollTimeElapsed=0;
  setprop(""~myNodeName~ "/orientation/rollTimeElapsed", rollTimeElapsed+updateinterval_sec);
 
  atts=attributes[myNodeName].attacks;
   
  if (atts.rollRateMax_degpersec==nil or atts.rollRateMax_degpersec<=0) 
          atts.rollRateMax_degpersec=50;
  var rolltime= math.abs(rolldegrees/atts.rollRateMax_degpersec);
  
  #debprint ("Bombable: acturn, time: ", rolltime, " rolldeg ", rolldegrees);

  
  #rolltime=2; #seconds to reach rolldegrees
  if (rolltime<updateinterval_sec) rolltime=updateinterval_sec;
  #props.globals.getNode(""~myNodeName~ "/position");
  #ac_position=props.globals.getNode(myNodeName, 1).getParent().getPath();
  var rollTimeElapsed=getprop(""~myNodeName~ "/orientation/rollTimeElapsed");
  if (rollTimeElapsed==nil) rollTimeElapsed=0;
  delta_deg=rolldegrees*updateinterval_sec/rolltime; #31/second for rolltime seconds
  currRoll_deg=getprop(""~myNodeName~ "/orientation/roll-deg-bombable");
  if (currRoll_deg==nil) currRoll_deg=0;  
  targetRoll_deg= currRoll_deg+delta_deg;
  #Fg turns too quickly to be believable if the roll gets about 78 degrees 
  # or so.  
  #rolldegrees is supposed to put a limit on the max amount of roll allowed
  #for this maneuver
  if (math.abs(targetRoll_deg) > math.abs(rolldegrees)) targetRoll_deg = math.abs(rolldegrees) * math.sgn (targetRoll_deg);
  
  #whereas roll_limit_deg is the absolute max for the aircraft
	if (math.abs(targetRoll_deg)>math.abs(roll_limit_deg)) targetRoll_deg=math.abs(roll_limit_deg)*math.sgn(targetRoll_deg);
	#debprint ("Bombable: Limit: ", roll_limit_deg, " rolldeg ", targetRoll_deg);
	
	#rollMax_deg=getprop(""~myNodeName~"/bombable/attributes/attacks/rollMax_deg");
	var rollMax_deg = atts.rollMax_deg;	
	if (rollMax_deg==nil) rollMax_deg = 50;
	if (math.abs(targetRoll_deg)>rollMax_deg) targetRoll_deg=rollMax_deg*math.sgn(targetRoll_deg);
	
	#if (math.abs (currRoll_deg - targetRoll_deg)> 5) debprint ("Bombable: Changing roll: ",  -currRoll_deg + targetRoll_deg, " ", myNodeName, " 3085");


	
	#debprint ("Bombable: setprop 2937");
  #debprint ("Bombable: Setting roll-deg for ", myNodeName , " to ", targetRoll_deg, " 3086");
  setprop (""~myNodeName~ "/orientation/roll-deg", targetRoll_deg);
  setprop (""~myNodeName~ "/orientation/roll-deg-bombable", targetRoll_deg);
  
  #set the target altitude as well.  flight/target-alt is in ft  
  if (targetAlt_m != "none") {
      #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
      var evas = attributes[myNodeName].evasions;
      var alts = attributes[myNodeName].altitudes;
      var vels = attributes[myNodeName].velocities;
      
      targetAlt_ft=targetAlt_m / FT2M;
      
  
      currElev_m=elev (any_aircraft_position(myNodeName).lat(),geo.aircraft_position(myNodeName).lon() )*feet2meters;
  
      if (targetAlt_m - currElev_m  < alts.minimumAGL_m ) targetAlt_ft = (alts.minimumAGL_m + currElev_m)/feet2meters;
      if (targetAlt_m - currElev_m  > alts.maximumAGL_m ) targetAlt_ft = (alts.maximumAGL_m + currElev_m)/feet2meters;
  
      #debprint ("Bombable: setprop 2955");
      # we set the target altitude, unless we are stalling and trying to move
      # higher, then we basically stop moving up      
      var stalling=getprop ("" ~ myNodeName ~ "/bombable/stalling");
      if (!stalling or targetAlt_m < currElev_m )       
        setprop ( "" ~ myNodeName ~ "/controls/flight/target-alt", targetAlt_ft );
      else {
        setprop (""~myNodeName~"/controls/flight/target-alt", currElev_m*meters2feet - 20 );
      }   
            
      currAlt_ft=getprop ("" ~ myNodeName ~ "/position/altitude-ft");
      dodgeAltAmount_ft=targetAlt_ft-currAlt_ft;
      if (dodgeAltAmount_ft > evas.dodgeAltMax_ft) dodgeAltAmount_ft = evas.dodgeAltMax_ft;
      if (dodgeAltAmount_ft < evas.dodgeAltMin_ft) dodgeAltAmount_ft = evas.dodgeAltMin_ft; 
      dodgeVertSpeed_fps=0;
       
      aircraftSetVertSpeed (myNodeName, dodgeAltAmount_ft, "atts");      

      #debprint ("Attacking: ", myNodeName, " ", dodgeAltAmount_ft, " ", dodgeVertSpeed_fps);
      
      
  }
  
  #debprint ("2672 ", getprop (""~myNodeName~"/controls/flight/target-alt")) ;
  
  #debprint("Bombable: RollControl: delta=",delta_deg, " ",targetRoll_deg," ", myNodeName);
  # Make it roll:    
  setprop(""~myNodeName~ "/orientation/rollTimeElapsed", rollTimeElapsed+updateinterval_sec);
  
  cutoff=math.abs(rolldegrees)/5;
  if (cutoff<1) cutoff=1;
  #wait a while & then roll back.  correction makes sure we don't keep
  # doing this repeatedly                              
  if ( math.abs(delta_heading_deg) > cutoff and rollTimeElapsed < maxTurnTime ) settimer (func { aircraftTurnToHeadingControl(myNodeName, loopid, targetdegrees, rolldegrees, targetAlt_m, roll_limit_deg)}, updateinterval_sec );
  else { 
    setprop(""~myNodeName~ "/orientation/rollTimeElapsed", 0);
    #debprint ("Bombable: Ending aircraft turn-to-heading routine");
    #aircraftRoll(myNodeName, 0, rolltime, roll_limit_deg);
    #debprint ("Bombable: setprop 3008");
    setprop(""~myNodeName~"/controls/flight/target-hdg", targetdegrees);
  }   
}

######################################################
# make an aircraft turn to a certain heading
#
var aircraftTurnToHeading = func (myNodeName, targetdegrees=0, rolldegrees=45, targetAlt_m="none", roll_limit_deg=85, favor="normal" ) {                                                                          
  #if (crashListener != 0 ) return;
  #debprint ("Bombable: Starting aircraft turn-to-heading routine");
  #same as roll-loopid ID because we can't do this & roll @ the same time
  var loopid = getprop(""~myNodeName~"/bombable/loopids/roll-loopid");
  if (loopid==nil) loopid=0; 
  loopid +=1;
  setprop(""~myNodeName~"/bombable/loopids/roll-loopid", loopid);
  
  setprop(""~myNodeName~ "/orientation/rollTimeElapsed", 0);
  
  targetdegrees=normdeg180(targetdegrees);
  rolldegrees=normdeg180(rolldegrees);

  #debprint ("Bombable: Starting turn-to-heading routine, loopid=",loopid, " ", rolldegrees, " ", targetdegrees);
  #props.globals.getNode(""~myNodeName~ "/orientation/rollTimeElapsed", 1).setValue( 0 );
  currRoll_deg=getprop (""~myNodeName~ "/orientation/roll-deg");
  if (currRoll_deg==nil) currRoll_deg=0;
  props.globals.getNode(""~myNodeName~ "/orientation/roll-deg-bombable", 1).setValue( currRoll_deg );

   start_heading_deg=getprop (""~myNodeName~"/orientation/true-heading-deg");
   delta_heading_deg = normdeg180(targetdegrees-start_heading_deg);
   
   #if close to 180 degrees off we sometimes/randomly choose to turn the
   # opposite direction.  Just for variety/reduce robotic-ness.   
   #if (math.abs(delta_heading_deg)> 150 and favor=="opposite") {
   #   targetdegrees=start_heading_deg-delta_heading_deg;
   #   } 

  
  aircraftTurnToHeadingControl (myNodeName, loopid, targetdegrees, rolldegrees, targetAlt_m, roll_limit_deg);  
  #turn it off after 10 seconds
  #settimer (func {removelistener(crashListener); crashListener=0;}, 10);
  
}


######################################
# internal - for making AI aircraft roll/turn
# rolldegrees means the absolute roll degrees to move to, from whatever
# rolldegrees the AC currently is at.
var aircraftRollControl = func (myNodeName, id, rolldegrees=-90, rolltime=5, roll_limit_deg=85) {
  
  var loopid = getprop(""~myNodeName~"/bombable/loopids/roll-loopid"); 
	id == loopid or return;
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
	
	#At a certain roll degrees aircraft behave very unrealistically--turning
	#far too fast etc. This is somewhat per aircraft and per velocity, but generally
  #anything more than 85 degrees just makes them turn on a dime rather
  #than realistically. 90 degrees is basically instant turn, so we're going 
  # to disallow that, but allow anything up to that. 
  
	if (math.abs(rolldegrees)>= 90 ) rolldegrees=88*math.sgn(rolldegrees);
  
  var updateinterval_sec=.1;
  if (rolltime<updateinterval_sec) rolltime=updateinterval_sec;
  #props.globals.getNode(""~myNodeName~ "/position");
  #ac_position=props.globals.getNode(myNodeName, 1).getParent().getPath();
  var rollTimeElapsed=getprop(""~myNodeName~ "/orientation/rollTimeElapsed");
  if (rollTimeElapsed==nil) rollTimeElapsed=0;
  var startRoll_deg=getprop(""~myNodeName~ "/orientation/start-roll-deg");
  if (startRoll_deg==nil) startRoll_deg=0;
  delta_deg=(rolldegrees-startRoll_deg)*updateinterval_sec/rolltime; 
  currRoll_deg=getprop(""~myNodeName~ "/orientation/roll-deg-bombable");
  if (currRoll_deg==nil) currRoll_deg=0;  
  targetRoll_deg= currRoll_deg+delta_deg;
  #Fg turns too quickly to be believable if the roll gets about 78 degrees 
  # or so.  
  #Fg seems to go totally whacky if the roll gets to, or close to, 90 degrees
  if (targetRoll_deg >  roll_limit_deg ) targetRoll_deg = roll_limit_deg;
  if (targetRoll_deg < -roll_limit_deg) targetRoll_deg =-roll_limit_deg;
  
  
  if (math.abs(targetRoll_deg)>roll_limit_deg) targetRoll_deg=roll_limit_deg*math.sgn(targetRoll_deg);
	#rollMax_deg=getprop(""~myNodeName~"/bombable/attributes/attacks/rollMax_deg");
	rollMax_deg = attributes[myNodeName].attacks.rollMax_deg;	
	if (rollMax_deg==nil) rollMax_deg = 50;
	if (math.abs(targetRoll_deg)>rollMax_deg) targetRoll_deg=rollMax_deg*math.sgn(targetRoll_deg);
  
 	#if (math.abs (currRoll_deg - targetRoll_deg)> 5) debprint ("Bombable: Changing roll: ", currRoll_deg - targetRoll_deg, " ", myNodeName, " 3238");
  
  #debprint ("Bombable: setprop 3071");     
  #debprint ("Bombable: Setting roll-deg for ", myNodeName , " to ", targetRoll_deg, " 3240");
  setprop (""~myNodeName~ "/orientation/roll-deg", targetRoll_deg);
  
  
  #we keep the 'uncorrected' amount internally because normal behavior
  # is to go to a certain degree & then return.  If we capped at 85 deg
  # then we would end up returning too far    
  setprop (""~myNodeName~ "/orientation/roll-deg-bombable", currRoll_deg+delta_deg);
  
  #debprint("Bombable: RollControl: delta=",delta_deg, " ",targetRoll_deg," ", myNodeName);
  # Make it roll:    
  setprop(""~myNodeName~ "/orientation/rollTimeElapsed", rollTimeElapsed+updateinterval_sec);
                            
  if ( rollTimeElapsed < rolltime ) settimer (func { aircraftRollControl(myNodeName, loopid, rolldegrees, rolltime, roll_limit_deg)}, updateinterval_sec, roll_limit_deg );
  else { 
    setprop(""~myNodeName~ "/orientation/rollTimeElapsed", 0);
    #debprint ("Bombable: Ending aircraft roll routine");
  }   
}

##################################################################
# Will roll the AC from whatever roll deg it is at, to rolldegrees in
# rolltime
var aircraftRoll = func (myNodeName, rolldegrees=-60, rolltime=5, roll_limit_deg=85) {
                                                                          
  #if (crashListener != 0 ) return;
  #debprint ("Bombable: Starting aircraft roll routine");
  
  
  var loopid = getprop(""~myNodeName~"/bombable/loopids/roll-loopid");
  if (loopid==nil) loopid=0; 
  loopid +=1;
  setprop(""~myNodeName~"/bombable/loopids/roll-loopid", loopid);

  debprint ("Bombable: Starting roll routine, loopid=",loopid, " ", rolldegrees, " ", rolltime);
  props.globals.getNode(""~myNodeName~ "/orientation/rollTimeElapsed", 1).setValue( 0 );
  currRoll_deg=getprop (""~myNodeName~ "/orientation/roll-deg");
  if (currRoll_deg==nil) currRoll_deg=0;
  props.globals.getNode(""~myNodeName~ "/orientation/roll-deg-bombable", 1).setValue( currRoll_deg );
  props.globals.getNode(""~myNodeName~ "/orientation/start-roll-deg", 1).setValue( currRoll_deg );

  aircraftRollControl(myNodeName, loopid, rolldegrees, rolltime, roll_limit_deg);
  
  #turn it off after 10 seconds
  #settimer (func {removelistener(crashListener); crashListener=0;}, 10);
  
}


var aircraftCrashControl = func (myNodeName) {

  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
  
  #If we reset the damage levels, stop crashing:
  if (getprop(""~myNodeName~"/bombable/attributes/damage")<1 )return;  
  
  var loopTime=.1;
  #props.globals.getNode(""~myNodeName~ "/position");
  #ac_position=props.globals.getNode(myNodeName, 1).getParent().getPath();
  elapsed=getprop(""~myNodeName~ "/position/crashTimeElapsed");
  if (elapsed==nil) elapsed=0;
  delta_ft=5.87*elapsed/(elapsed+5); #we're using 176 ft/sec as the terminal velocity & runninG this loop 30X per second
  # t/(t+5) is a crude approximation of tanh(t), which is the real equation
  # to use for terminal velocity under gravity.  However tanh is very expensive
  # and since we have to approximate the coefficient of drag and other variables
  # related to the damaged aircraft anyway, based on very incomplete information,
  # this approximation is about good enough and definitely much faster than tanh        
  currAlt_ft=getprop(""~myNodeName~ "/position/altitude-ft");
  
  #debprint ("Bombable: setprop 3128");  
  setprop (""~myNodeName~ "/position/altitude-ft", currAlt_ft-delta_ft);
  #debprint("Bombable: CrashControl: delta=",delta_ft, " ",currAlt_ft," ", myNodeName);
  # Make it roll:  
 
  #debprint ("Bombable: Setting roll-deg for ", myNodeName , " to ", -elapsed*5*delta_ft, " 1610");    
  setprop (""~myNodeName~ "/orientation/roll-deg", -elapsed*5*delta_ft);  
  setprop(""~myNodeName~ "/position/crashTimeElapsed", elapsed+loopTime);
                            
  var onGround= getprop (""~myNodeName~"/bombable/on-ground");
  if (onGround==nil) onGround=0;
  
  #the main aircraft.  This is experimental/non-working.
  if (myNodeName=="") {
  
      
      var objectGeoCoord = geo.Coord.new();
	
	    objectGeoCoord.set_latlon(getprop("position/latitude-deg"), getprop("position/longitude-deg"), getprop("position/altitude-ft")*feet2meters);
	    
      var velocity_kt=getprop("/velocities/groundspeed-kt");
      var heading_deg= getprop("/orientation/heading-deg");
      
	
	    objectGeoCoord.apply_course_distance(heading_deg, velocity_kt* 0.514444444 * loopTime);  
	    
	    #debprint ("Bombable: setprop 3151");
      setprop("/position/latitude-deg", objectGeoCoord.lat());
	    setprop("/position/longitude-deg", objectGeoCoord.lon());
	
	    if (getprop("/position/altitude-agl-ft") <=5) onGround=1;
	    
	    #exit this immediately if we become un-crashed
	    if (!getprop("/sim/crashed")) return;
	
  }    
	    
	
      

  # elevation of -1371 ft is a failsafe (lowest elevation on earth); so is 
  #   elapsed, so that we don't get stuck in this routine forever  
  if ( onGround != 1 and currAlt_ft>-1371 and elapsed < 240 ) settimer (func { aircraftCrashControl(myNodeName)}, loopTime + loopTime*(rand()/10-1/20) );
  else { 
    setprop(""~myNodeName~ "/position/crashTimeElapsed", 0);
    #we should be crashed at this point but just in case:
    if ( currAlt_ft<=-1371 ) add_damage(1, myNodeName,"crash");
    debprint ("Bombable: Ending aircraft crash routine");
  }   
}

var aircraftCrash = func (myNodeName) {
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
  #if (myNodeName=="/environment" or myNodeName=="environment") myNodeName="";
                               
  #if (myNodeName=="") debprint ("Bombable: Updating main aircraft 3154");
                                                                                    
  #if (crashListener != 0 ) return;
  debprint ("Bombable: Starting aircraft crash routine");
  elapsed=props.globals.getNode(""~myNodeName~ "/position/crashTimeElapsed", 1).getValue( );
  if (elapsed==nil) elapsed=0;
  debprint ("Bombable: Starting crash routine, elapsed=",elapsed);
  if (elapsed!=0) return;
  props.globals.getNode(""~myNodeName~ "/position/crashTimeElapsed", 1).setValue( .1 );
  aircraftCrashControl(myNodeName);
  
  #turn it off after 10 seconds
  #settimer (func {removelistener(crashListener); crashListener=0;}, 10);
  
}

##
# return string converted into nasal variable/proptree safe form
#
var variable_safe = func(str) {
	var s = "";
	if (str==nil) return s;
	if (size(str)>0 and !string.isalpha(str[1])) s="_"; #make sure we always start with alpha char OR _
	for (var i = 0; i < size(str); i += 1) {
	   if (string.isalnum(str[i]) or str[i]==`_` )
	   		s ~= chr(str[i]);
	   if (str[i]==` ` or str[i]==`-` or str[i]==`.`) s~="_";		  
	}   
	return s;
}

##
# return string converted from nasal variable/proptree safe form
# back into human readable form
#
var un_variable_safe = func(str) {
	var s = "";
	for (var i = 0; i < size(str); i += 1) {
	   if (str[i]==`_` and i !=1 )	s~=" "; #ignore initial _, that is only to make a numeric value start with _ so it is a legal variable name
	   else s ~= chr(str[i]);		
	}   
	return s;
}

#######################################################################
# insertionSort
# a = a vector
# f = a function of two variables, f(a,b) which returns > 0 if a>b
# The default sort is by string; see below
#   
var insertionSort = func (a=nil, f=nil ) {

 #the default is to sort by string for all values, including numbers
 #but if some of the values are numbers we have to convert them to string 
 if (f==nil) f = func(a, b) { 
     if (num(a)==nil) var acomp=a else var acomp=sprintf("%f", a);
     if (num(b)==nil) var bcomp=b else var bcomp=sprintf("%f", b);
     cmp (acomp,bcomp);
  };

 for (var i=1; i<size(a); i+=1) {
   var value=a[i];
   var j=i-1;
   var done = 0;
   while (!done) {
    if (f(a[j], value)> 0 ) {
      a[j+1]=a[j];
      j-=1;
      if (j<0) done=1;
      
    } else {done=1}; 
   }
   a[j+1]=value;
 }
 return(a);
}


##########################################################
# CLASS records
# 
# Class for keeping stats on hits & misses, printing & 
# displaying stats, etc.
#  
var records = {};

records.init = func () { 
       me.impactTotals = {};
       me.impactTotals.Overall = {};  
       me.impactTotals.Overall.Total_Impacts = 0;
       me.impactTotals.Overall.Damaging_Impacts = 0;
       me.impactTotals.Overall.Total_Damage_Added = 0;
       me.impactTotals.Overall.sort = "0";
       me.impactTotals.Objects={};
       me.impactTotals.Objects.sort = 10;
       me.impactTotals.Ammo_Categories={};
       me.impactTotals.Ammo_Categories.sort = 20;
       me.impactTotals.Ammo_Type={};
       me.impactTotals.Ammo_Type.sort = 30;
}
 
records.record_impact = func ( myNodeName="", damageRise=0, damageIncrease=0, damageValue=0, impactNodeName=nil, ballisticMass_lb=nil, lat_deg=nil, lon_deg=nil, alt_m=nil ) {
      
       # we will get damaging impacts twice--once from add_damage
       # and once from put_splash.  So we count total impacts from
       # put_splash (damageRise==0) and damaging impacts from 
       # add_damage (damageRise >=0).                     
       if (damageRise > 0 ) me.impactTotals.Overall.Damaging_Impacts+=1;
       else me.impactTotals.Overall.Total_Impacts+=1;
       
       me.impactTotals.Overall.Total_Damage_Added += 100*damageRise;
       
       
       var weaponType=nil;
       if (impactNodeName!=nil) weaponType = getprop (""~impactNodeName~"/name");
       var ballCategory = nil;
       if ( ballisticMass_lb < 1) ballCategory="Small arms";
       elsif ( ballisticMass_lb <= 10) ballCategory="1-10 pound ordinance";
       elsif ( ballisticMass_lb <= 100) ballCategory="11-100 pound ordinance";
       elsif ( ballisticMass_lb <= 500) ballCategory="101-500 pound ordinance";
       elsif ( ballisticMass_lb <= 1000) ballCategory="501-1000 pound ordinance";
       elsif ( ballisticMass_lb > 1000) ballCategory="Over 1000 pound ordinance"; 

       var callsign = getCallSign (myNodeName);
       if (myNodeName=="") callsign = nil;  
              
       var items = [callsign, weaponType, ballCategory];             
       for (var count=0; count<size (items); count+=1  ) {
         var item = items[count];
         if (item==nil or item=="") continue;
         
         var i= variable_safe (item);
         var category="Objects";
         if (item==weaponType)  category="Ammo_Type";
         if (item==ballCategory) category="Ammo_Categories";
         
         var sort=count*10 + 10; #overall is 1, then they come in order as listed in items
         
         
         
         
         if (! contains ( me.impactTotals, category)) {
           me.impactTotals[category] = {};
           me.impactTotals[category].sort = sort;
         }
         
         var currHash=me.impactTotals[category];
         
         if (! contains (currHash, i) ){
             currHash[i]={};
             
             #We don't save impacts per callsign, because misses & terrain
             # impacts can be picked up by any AI object or the main AC in a
             # fairly random/meaningless fashion                          
             if (count!=0) currHash[i].Total_Impacts = 0;
             currHash[i].Damaging_Impacts = 0;
             currHash[i].Total_Damage_Added = 0;
             
         }
         
         if ( damageRise > 0 ) currHash[i]["Damaging_Impacts"]+=1;
         elsif (currHash[i]["Total_Impacts"]!=nil) currHash[i]["Total_Impacts"]+=1; 

         currHash[i].Total_Damage_Added += 100*damageRise; 
       
       }                          

}                                                 

records.sort_keys = func {
        #the sort functin is malfunctioning in some bizarre way so for now 
        #     we just return the keys unsorted
                
        #me.sortkey=keys(me.impactTotals);
        #var k= keys(me.impactTotals);
        #var l=k[:]; #a copy of the keys         
        #me.sortkey=sort(l, func(a, b) cmp(a, b));        
        #return;
        
                
        #var hash= {a:1, b:2};
        var hash = me.impactTotals;        
        var k=keys(hash);
        #me.sortkeys = sort (k, func (a, b) {cmp (a,b)} );
        #me.sortkeys = sort (k, func (a, b) { cmp (a.sort, b.sort) } ); 
        #me.sortkey = sort(k, func(a, b) cmp(hash[a].sort, hash[b].sort));        
#            if ( hash[a]["sort"] < hash[b]["sort"]) -1;
#            elsif (hash[a]["sort"] > hash[b]["sort"]) 1;
#            else 0; 
#        }  );
        #
      
      
      me.sortkey = insertionSort(k, func(a, b) { 
         #sort by string for all values, including numbers
         #but if some of the values are numbers we have to convert them to string 
         if (num(hash[a].sort)==nil) var acomp=hash[a].sort else var acomp=sprintf("%f", hash[a].sort);
         if (num(hash[b].sort)==nil) var bcomp=hash[b].sort else var bcomp=sprintf("%f", hash[b].sort);
         cmp (acomp,bcomp);
      });
}
  
records.display_results = func {
        
        debug.dump (me.impactTotals);
        me.show_totals_dialog(); 
      
}
  
records.add_property_tree = func (location, hash ) {    
       # not working, we have spaces in our names
       props.globals.getNode(location,1).removeChildren();
       props.globals.getNode(location,1).setValues( hash );
       return props.globals.getNode(location); 
}     

records.create_printable_summary = func (obj, sortkey=nil, prefix="") {
  var msg="";
  if (typeof(obj)!="hash") return;
  if (sortkey==nil) sortkey = keys(obj);
  
  foreach (var i; sortkey) {

       #if (typeof (obj[i])=="hash")  msg ~= "\n" ~ me.create_printable_summary (obj[i],keys(obj));
       #elsif (i!="sort") {
               #var num= sprintf("%1.0f", obj[i]);
               #msg ~= "  " ~ un_variable_safe(i) ~ ": " ~ num ~ "\n";
       #}   
       if (typeof(obj[i])=="hash" ) { 
             msg ~= prefix ~ un_variable_safe (i) ~ ": \n";
             msg ~= me.create_printable_summary (obj[i],keys(obj[i]), prefix~"  ");
       } elsif ( i != "sort" ) {
             var num= sprintf("%1.0f", obj[i]);
             msg ~= prefix ~ "  " ~ un_variable_safe(i) ~ ": " ~ num ~ "\n";
       } 

  }                                     
  return msg;
}
 
records.show_totals_dialog = func {
       var totals= {
         title: "Bombable Impact Statistics Summary",
         line: "Note: Rounds which do not impact terrain or an AI object are not recorded" 
       };
       me.sort_keys();
       totals.text=me.create_printable_summary (me.impactTotals, me.sortkey);
       node = me.add_property_tree ("/bombable/records", me.impactTotals);
       node = me.add_property_tree ("/bombable/dialogs/records", totals);
       gui.showHelpDialog ("/bombable/dialogs/records");
       
}  
     

################################################################
#function adds damage to an AI aircraft 
#(called by the fire loop and ballistic impact
#listener function, typically)
# returns the amount of damage added (which may be smaller than the damageRise requested, for various reasons)
# damagetype is "weapon" or "nonweapon".  nonweapon damage (fire, crash into 
# ground, etc) is not passed on via multiplayer (fire, crash, etc damage is 
# handled on their end and if all connected players add fire & crash damage via 
# multiplayer, too, then it creates a nasty cascade)
# Also slows down the vehicle whenever damage increases.
# vuls.damageVulnerability multiplies the damage, with an M1 tank = 1.  vuls.damageVulnerability=2
# means 2X the damage.
# maxSpeedReduce is a percentage, the maximum percentage to reduce speed
# in one step.  An airplane might keep moving close to the same speed
# even if the engine dies completely.  A tank might stop forward motion almost
# instantly.
var add_damage = func(damageRise, myNodeName, damagetype="weapon", impactNodeName=nil, ballisticMass_lb=nil, lat_deg=nil, lon_deg=nil, alt_m=nil  ) {
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return 0;
  if (myNodeName=="") {
    damAdd=mainAC_add_damage(damageRise, 0,"weapons", "Damaged by own weapons!");
    return damAdd;
  }
  node = props.globals.getNode(myNodeName);
  
  
  debprint ("Bombable: add_damage ", myNodeName); 
  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  var vuls= attributes[myNodeName].vulnerabilities;
	var spds= attributes[myNodeName].velocities; 
  var livs= attributes[myNodeName].damageLiveries;
  var liveriesCount= livs.count;
  var type=node.getName();
  var damageValue = getprop(""~myNodeName~"/bombable/attributes/damage");
  if ( damageValue==nil ) damageValue=0;
    
  var origDamageRise = damageRise;
  #make sure it's in range 0-1.0
  if(damageRise > 1.0)
			damageRise = 1.0;
	elsif(damageRise < 0.0)
			damageRise = 0.0;
  
  # update bombable/attributes/damage: 0.0 mean no damage, 1.0 mean full damage
  prevDamageValue=damageValue;
	if(damageValue < 1.0) 
		damageValue += damageRise;
		
  #make sure it's in range 0-1.0
  if(damageValue > 1.0)
			damageValue = 1.0;
	elsif(damageValue < 0.0)
			damageValue = 0.0;
	setprop(""~myNodeName~"/bombable/attributes/damage", damageValue);
	damageIncrease= damageValue - prevDamageValue;
  
     
  if (damagetype=="weapon") records.record_impact ( myNodeName, damageRise, damageIncrease, damageValue, impactNodeName, ballisticMass_lb, lat_deg, lon_deg, alt_m );   
     

	#debprint ("damageValue=",damageValue);
	var callsign = getCallSign (myNodeName);  
    	
	#if (int(damageValue * 20 )!=int(prevDamageValue * 20 )) {
	# 
	# 
	    	
  if ( damageValue>prevDamageValue ) {
  
  damageRiseDisplay= round( damageRise*100 );
	if (damageRise <.01) damageRiseDisplay = sprintf ("%1.2f",damageRise*100);
  elsif (damageRise <.1) damageRiseDisplay = sprintf ("%1.1f",damageRise*100);
  
  
     var msg= "Damage added: " ~ damageRiseDisplay ~ "% - Total damage: " ~ round ( damageValue * 100 ) ~ "% for " ~  string.trim(callsign);
     debprint ("Bombable: " ~ msg ~ " (" ~ myNodeName ~ ", " ~ origDamageRise ~")" );
     
     #Always display the message if a weapon hit or large damageRise. Otherwise
     #only display about 1 in 20 of the messages.
     #If we don't do this the small 0.4 damageRises from fires overwhelm the message area
     #and we don't know what's going on.
     if (damagetype == "weapon" or damageRise >4 or rand()<.05) targetStatusPopupTip (msg, 20);

      
  }   	

  if ( damageValue==1 and damageValue>prevDamageValue and type == "aircraft") {
    aircraftCrash (myNodeName);
  }

  var onGround= getprop (""~myNodeName~"/bombable/on-ground");
  if (onGround==nil) onGround=0;
  
  if (onGround) {
  
      #all to a complete stop
      #debprint ("Bombable: setprop 3263");
      setprop(""~myNodeName~"/controls/tgt-speed-kts", 0);

      setprop(""~myNodeName~"/controls/flight/target-spd", 0); 
         
      setprop(""~myNodeName~"/velocities/true-airspeed-kt", 0); 
      
      #we hit the ground, now we are 100% dead
      setprop(""~myNodeName~"/bombable/attributes/damage", 1);
      
      if (liveriesCount > 0 and liveriesCount != nil ) {
      
      livery = livs.damageLivery [ int ( damageValue * ( liveriesCount - 1 ) ) ];
  	   setprop(""~myNodeName~"/bombable/texture-corps-path", 
         livery );
		  }
    	   	    	
       
      return  damageIncrease;
  } 
  
  
  #debprint (damageRise, " ", myNodeName);
  #max speed reduction due to damage, in %
  
  minSpeed = trueAirspeed2indicatedAirspeed (myNodeName, spds.minSpeed_kt);
   
  #if the object is "on the ground" or "completely sunk" due to damage
  # then we make it come to a stop much more dramatically  
  #if ( onGround){
  #   if (spds.maxSpeedReduce_percent<20)  spds.maxSpeedReduce_percent=20;
  #   minSpeed=0;
  #   onGround=1;
  #} else onGround=0;
  
  
  #for moving objects (ships & aircraft), reduce velocity each time damage added
	#eventually  stopping when damage = 1.  
	#But don't reduce speed below minSpeed.
	#we put it here outside the "if" statement so that burning
	#objects continue to slow/stop even if their damage is already at 1
	# (this happens when file/reset is chosen in FG)
	var tgt_spd_kts=getprop (""~myNodeName~"/controls/tgt-speed-kts"); 
  if (tgt_spd_kts == nil ) tgt_spd_kts=0;

	var flight_tgt_spd=getprop (""~myNodeName~"/controls/flight/target-spd"); 
  if (flight_tgt_spd == nil ) flight_tgt_spd=0;
    
  var true_spd=getprop (""~myNodeName~"/velocities/true-airspeed-kt");
  if (true_spd == nil ) true_spd=0; 
  
  maxSpeedReduceProp=1-spds.maxSpeedReduce_percent/100;  #spds.maxSpeedReduce_percent is a percentage
  speedReduce= 1-damageValue;
  if (speedReduce < maxSpeedReduceProp) speedReduce=maxSpeedReduceProp;
  
  pitch=getprop (""~myNodeName~"/orientation/pitch-deg");
  
  var node = props.globals.getNode(myNodeName);
  

  #debprint ("type=", type);
  
  if (type=="aircraft")  {
      
      #if (pitch > - 90)
      #      setprop (""~myNodeName~"/orientation/pitch-deg", pitch-1);
            


      if ( damageValue >= 0.75 and !onGround) {    
          #debprint ("Bombable: setprop 3333");
          if (flight_tgt_spd > minSpeed) 
              setprop(""~myNodeName~"/controls/flight/target-spd", 
              flight_tgt_spd * speedReduce);
          else setprop(""~myNodeName~"/controls/flight/target-spd", 
             minSpeed);  
      }
  
  #ships etc we control all these ways, making sure the speed decreases but
  #not below the minimum allowed
  }  else {     
    #debprint ("Bombable: setprop 3344");
    if (tgt_spd_kts > minSpeed)  
      setprop(""~myNodeName~"/controls/tgt-speed-kts", 
         tgt_spd_kts * speedReduce);    

    if (flight_tgt_spd > minSpeed) 
      setprop(""~myNodeName~"/controls/flight/target-spd", 
         flight_tgt_spd * speedReduce);
         
    if (true_spd > minSpeed) 
      setprop(""~myNodeName~"/velocities/true-airspeed-kt", 
         true_spd * speedReduce);				
  }  
    

		var fireStarted=getprop(""~myNodeName~"/bombable/fire-particles/fire-burning");
		if (fireStarted == nil ) fireStarted=0;
   	var damageEngineSmokeStarted=getprop(""~myNodeName~"/bombable/fire-particles/damagedengine-burning");
   	if (damageEngineSmokeStarted == nil ) damageEngineSmokeStarted = 0; 
   	
   	#don't print this for every fire damage rise, but otherwise . . .
   	#if (!fireStarted or damageRise > vuls.fireDamageRate_percentpersecond * 2.5 ) debprint ("Damage added: ", damageRise, ", Total damage: ", damageValue);
    #Start damaged engine smoke but only sometimes; greater chance when hitting an aircraft
   	
   	
   	if (!damageEngineSmokeStarted and !fireStarted and rand() < damageRise * vuls.engineDamageVulnerability_percent / 2 ) 
        startSmoke("damagedengine",myNodeName);
       

	  # start fire if there is enough damages.
		#if(damageValue >= 1 - vuls.fireVulnerability_percent/100 and !fireStarted ) {
				
    #a percentage change of starting a fire with each hit
		if( rand() < .035 * damageRise * (vuls.fireVulnerability_percent) and !fireStarted ) {
		
		  debprint ("Bombable: Starting fire");
			
			#use small, medium, large smoke column depending on vuls.damageVulnerability
			#(high vuls.damageVulnerability means small/light/easily damaged while 
			# low vuls.damageVulnerability means a difficult, hardened target that should burn
			# more vigorously once finally on fire)   
			#var fp="";      
			#if (vuls.explosiveMass_kg < 1000 ) { fp="AI/Aircraft/Fire-Particles/fire-particles-small.xml"; }
			#elsif (vuls.explosiveMass_kg > 50000 ) { fp="AI/Aircraft/Fire-Particles/fire-particles-large.xml"; }
			#else {fp="AI/Aircraft/Fire-Particles/fire-particles.xml";} 

      #small, med, large fire depending on size of hit that caused it			
			var fp="";      
			if (damageRise < 0.2 ) { fp="AI/Aircraft/Fire-Particles/fire-particles-very-small.xml"; }
			elsif (damageRise > 0.5 ) { fp="AI/Aircraft/Fire-Particles/fire-particles.xml"; }
			else {fp="AI/Aircraft/Fire-Particles/fire-particles-small.xml";}
      
      startFire(myNodeName, fp); 
      #only one damage smoke at a time . . . 
      deleteSmoke("damagedengine",myNodeName);
      
      
      #fire can be extinguished up to MaxTime_seconds in the future,
      #if it is extinguished we set up the damagedengine smoke so 
      #the smoke doesn't entirely go away, but no more damage added
      if ( rand() * 100 < vuls.fireExtinguishSuccess_percentage ) {
      
         settimer (func { 
           deleteFire (myNodeName);
           startSmoke("damagedengine",myNodeName); 
           } ,            
           rand() * vuls.fireExtinguishMaxTime_seconds + 15 ) ;
      }
           
;
#      debprint ("started fire");
    
    #Set livery to the one corresponding to this amount of damage
    if (liveriesCount > 0 and liveriesCount != nil ) {
      livery = livs.damageLivery [ int ( damageValue * ( liveriesCount - 1 ) ) ];
  	   setprop(""~myNodeName~"/bombable/texture-corps-path", 
         livery );
		
		}
	}
	#only send damage via multiplayer if it is weapon damage from our weapons
	if (type=="multiplayer" and damagetype == "weapon") {
     mp_send_damage(myNodeName, damageRise);
  };
  
  return  damageIncrease;
}


####################################################
#functions to increment loopids
#these are called on init and destruct (which should be called
#when the object loads/unloads)
#When the loopid increments it will kill any timer functions
#using that loopid for that object.  (Otherwise they will just
#continue to run indefinitely even though the object itself is unloaded)
var inc_loopid = func (nodeName="", loopName="") {
  #if (nodeName=="") nodeName="/environment";
	var loopid = getprop(""~nodeName~"/bombable/loopids/" ~ loopName ~ "-loopid"); 
	if ( loopid == nil ) loopid=0;
	loopid += 1;
	setprop(""~nodeName~"/bombable/loopids/" ~ loopName ~ "-loopid", loopid);
	return loopid;
}



#####################################################
# Set livery color (including normal through 
# slightly and then completely damaged)
#
# Example:
#
# liveries = [ 
#          "Models/livery_nodamage.png", 
#          "Models/livery_slightdamage.png", 
#          "Models/livery_highdamage.png"
#  ];
#  bombable.set_livery (cmdarg().getPath(), liveries);

var set_livery = func (myNodeName, liveries) {
  if (!getprop(bomb_menu_pp~"bombable-enabled") ) return;
  var node = props.globals.getNode(myNodeName);
  # var livs = node.getNode ("/bombable/attributes/damageLiveries",1).getValues();
  
  
  if (! contains (bombable.attributes, myNodeName)) bombable.attributes[myNodeName]={};
  bombable.attributes[myNodeName].damageLiveries={};
  var livs = bombable.attributes[myNodeName].damageLiveries;
  
  #set new liveries, also set the count to the number
  #of liveries installed
  if (liveries == nil or size ( liveries) == 0 ) {
     #livs.removeChildren();
     #node.getNode("bombable/attributes/damageLiveries/count", 1).setValue( 0 );
     livs.count=0;     
    
  } else {
    livs.damageLivery=liveries;
    livs.count= size (liveries) ;
    
    
  	#current color (we'll set it to the undamaged color;
    #if the object is on fire/damage damaged this will soon be updated)
    #by the timer function
    #To actually work, the aircraft's xml file must be set up with an 
    #animation to change the texture, keyed to the bombable/texture-corps-path
    #property
  	node.getNode("bombable/texture-corps-path", 1).setValue(liveries[0]);
  }
}

var checkRange = func (v=nil, low=nil, high=nil, default=1) {

 if ( v == nil ) v=default;
 if ( low != nil and v < low  ) v = low;
 if ( high != nil and v > high ) v = high;
 
 return v;
}

var checkRangeHash = func (b=nil, v=nil, low=nil, high=nil, default=1) {
 if (contains (b, v)) return checkRange (b[v],low, high, default)
 else return default;
 
}

######################################################################
######################################################################
######################################################################
#delaying all the _init functions until FG's initialization sequence
#has settled down seems to solve a lot of FG crashes on startup when 
#bombable is running with scenarios.  
#It takes about 60 seconds to get them all initialized.
#
var initialize = func (b) {
debprint ("Bombable: Delaying initialize . . . ", b.objectNodeName);
  settimer (func {initialize_func(b);}, 30, 1);

}


#####################################################
# initialize: Do sanity checking, then
# slurp the pertinent properties into
# the object's node tree under sub-node "bombable"
# so that they can be access by all the different
# subroutines
# 
# The new way: All these variables are stored in attributes[myNodeName]
# (myNodeName="" for the main aircraft).
# 
# This saves a lot of a reading/writing from the property tree,
# which turns out to be quite slow.
# 
# The old way:
# 
# If you just need a certain property or two you can simply read it 
# with getprops.
#
# But for those routines that use many/all we can just grab them all with
#  var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
#  bomb= b.getValues();  #all under the "bombable/attributes" branch
# Then use values like bomb.dimensions.width_m etc.
# Normally don't do this as it slurps in MANY values
#
# But (better if you only need one sub-branch)
#  dims= b.getNode("dimensions").getValues(); 
# Gets values from subbranch 'dimensions'.
# Then your values are dims.width_m etc.
#
#
var initialize_func = func ( b ){

 #only allow initialization for ai & multiplayer objects
 # in FG 2.4.0 we're having trouble with strange(!?) init requests from
 # joysticks & the like  
 var init_allowed=0;
 if (find ("/ai/models/", b.objectNodeName ) != -1 ) init_allowed=1;
 if (find ("/multiplayer/", b.objectNodeName ) != -1 ) init_allowed=1;

 if (init_allowed!=1) {
   debprint ("Bombable: Attempt to initialize a Bombable subroutine on an object that is not AI or Multiplayer; aborting initialization. ", b.objectNodeName);
   return;
 } 
 


 #do sanity checking on input
 #also calculate a few values that will be useful later on &
 #add them to the object

 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 # if it 1 and we're trying to initialize, something has gone wrong and we abort with a message.  
 var inited= getprop(""~b.objectNodeName~"/bombable/initializers/attributes-initialized");
 
 if (inited==1) {
   debprint ("Bombable: Attempt to re-initialize attributes when it has not been de-initialized; aborting re-initialization. ", b.objectNodeName);
   return;
 } 
 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 setprop(""~b.objectNodeName~"/bombable/initializers/attributes-initialized", 1);
 debprint( "Bombable: Initializing bombable attributes for ", b.objectNodeName);


  #initialize damage level of this object
  b.damage = 0;
  b.updateTime_s = checkRange ( b.updateTime_s, 0, 10, 1);
    
  ##altitudes sanity checking
  if (contains (b, "altitudes") and typeof (b.altitudes) == "hash") {  
    b.altitudes.wheelsOnGroundAGL_m = checkRange ( b.altitudes.wheelsOnGroundAGL_m, -1000000, 1000000, 0 );
    b.altitudes.minimumAGL_m = checkRange ( b.altitudes.minimumAGL_m, -1000000, 1000000, 0 );
    b.altitudes.maximumAGL_m = checkRange ( b.altitudes.maximumAGL_m, -1000000, 1000000, 0 );
    #keep this one negative or zero:
    b.altitudes.crashedAGL_m = checkRange ( b.altitudes.crashedAGL_m, -1000000, 0, -0.001 );
    if (b.altitudes.crashedAGL_m == 0 )b.altitudes.crashedAGL_m = -0.001;
    
    b.altitudes.initialized=0; #this is how ground_loop knows to initialize the alititude on its first call
    b.altitudes.wheelsOnGroundAGL_ft=b.altitudes.wheelsOnGroundAGL_m/feet2meters;
    b.altitudes.minimumAGL_ft=b.altitudes.minimumAGL_m/feet2meters;
    b.altitudes.maximumAGL_ft=b.altitudes.maximumAGL_m/feet2meters;
    b.altitudes.crashedAGL_ft=b.altitudes.crashedAGL_m/feet2meters;
      
    #crashedAGL must be at least a bit lower than minimumAGL
    if (b.altitudes.crashedAGL_m > b.altitudes.minimumAGL_m )
         b.altitudes.crashedAGL_m = b.altitudes.minimumAGL_m - 0.001;
  }
         
  #evasions sanity checking
  if (contains (b, "evasions") and typeof (b.evasions) == "hash") {
      
    b.evasions.dodgeDelayMax_sec = checkRangeHash ( b.evasions, "dodgeDelayMax_sec", 0, 600, 30 );
    b.evasions.dodgeDelayMin_sec = checkRangeHash ( b.evasions, "dodgeDelayMin_sec", 0, 600, 5 );
    if (b.evasions.dodgeDelayMax_sec< b.evasions.dodgeDelayMin_sec) 
      b.evasions.dodgeDelayMax_sec=b.evasions.dodgeDelayMin_sec;
    
    b.evasions.dodgeMax_deg = checkRangeHash ( b.evasions, "dodgeMax_deg", 0, 180, 90 );
    b.evasions.dodgeMin_deg = checkRangeHash ( b.evasions, "dodgeMin_deg", 0, 180, 30 );
    if (b.evasions.dodgeMax_deg< b.evasions.dodgeMin_deg) 
      b.evasions.dodgeMax_deg=b.evasions.dodgeMax_deg;

    b.evasions.rollRateMax_degpersec = checkRangeHash ( b.evasions, "rollRateMax_degpersec", 1, 720, 45 );
    
    if (b.evasions.dodgeROverLPreference_percent==nil) b.evasions.dodgeROverLPreference_percent=50;
    b.evasions.dodgeROverLPreference_percent = checkRangeHash ( b.evasions,"dodgeROverLPreference_percent", 0, 100, 50 );
    
    b.evasions.dodgeAltMax_m = checkRangeHash ( b.evasions, "dodgeAltMax_m", -100000, 100000, 20 ); 
    b.evasions.dodgeAltMin_m = checkRangeHash ( b.evasions, "dodgeAltMin_m", -100000, 100000, -20 );         
    if (b.evasions.dodgeAltMax_m < b.evasions.dodgeAltMin_m) 
      b.evasions.dodgeAltMax_m = b.evasions.dodgeAltMin_m;
    b.evasions.dodgeAltMin_ft = b.evasions.dodgeAltMin_m/feet2meters;
    b.evasions.dodgeAltMax_ft = b.evasions.dodgeAltMax_m/feet2meters;
    
    
    b.evasions.dodgeVertSpeedClimb_mps = checkRangeHash (b.evasions, "dodgeVertSpeedClimb_mps", 0, 3000, 0 );
    b.evasions.dodgeVertSpeedDive_mps = checkRangeHash ( b.evasions, "dodgeVertSpeedDive_mps", 0, 5000, 0 );          
    b.evasions.dodgeVertSpeedClimb_fps = b.evasions.dodgeVertSpeedClimb_mps/feet2meters;
    b.evasions.dodgeVertSpeedDive_fps = b.evasions.dodgeVertSpeedDive_mps/feet2meters;
  }  
  
  
  
  ##dimensions sanity checking  
  # Need to re-write checkRange so it integrates the check of whether b.dimensions.XXXX
  # even exists and takes appropriate action if not    
  if (contains (b, "dimensions") and typeof (b.dimensions) == "hash") {
    b.dimensions.width_m = checkRange ( b.dimensions.width_m, 0, nil , 30 );
    b.dimensions.length_m = checkRange ( b.dimensions.length_m, 0, nil, 30 );
    b.dimensions.height_m = checkRange ( b.dimensions.height_m, 0, nil, 30 );
    if (!contains(b.dimensions, "damageRadius_m")) b.dimensions.damageRadius_m=nil;
    b.dimensions.damageRadius_m =checkRange ( b.dimensions.damageRadius_m, 0, nil, 6 );
    if (!contains(b.dimensions, "vitalDamageRadius_m")) b.dimensions.vitalDamageRadius_m=nil;
    b.dimensions.vitalDamageRadius_m =checkRange ( b.dimensions.vitalDamageRadius_m, 0, nil, 2.5 );
    if (!contains(b.dimensions, "crashRadius_m")) b.dimensions.crashRadius_m=nil;
    b.dimensions.crashRadius_m = checkRange ( b.dimensions.crashRadius_m, 0, nil, b.dimensions.vitalDamageRadius_m );
     


    #add some helpful new:
    #   
    b.dimensions.width_ft = b.dimensions.width_m/feet2meters;
    b.dimensions.length_ft = b.dimensions.length_m/feet2meters;
    b.dimensions.height_ft = b.dimensions.height_m/feet2meters;   
    b.dimensions.damageRadius_ft = b.dimensions.damageRadius_m/feet2meters;
  }  
 
  ## velocities sanity checking
  if (contains (b, "velocities") and typeof (b.velocities) == "hash") {
    b.velocities.maxSpeedReduce_percent = checkRangeHash ( b.velocities, "maxSpeedReduce_percent", 0, 100, 1 );
    b.velocities.minSpeed_kt = checkRangeHash (b.velocities, "minSpeed_kt", 0, nil, 0 );
    b.velocities.cruiseSpeed_kt = checkRangeHash (b.velocities, "cruiseSpeed_kt", 0, nil, 100 );
    b.velocities.attackSpeed_kt = checkRangeHash (b.velocities, "attackSpeed_kt", 0, nil, 150 );
    b.velocities.maxSpeed_kt = checkRangeHash (b.velocities, "maxSpeed_kt", 0, nil, 250 );
    
    b.velocities.damagedAltitudeChangeMaxRate_meterspersecond = checkRangeHash (b.velocities, "damagedAltitudeChangeMaxRate_meterspersecond", 0, nil, 0.5 );
    
    if (contains (b.velocities, "diveTerminalVelocities") and typeof (b.velocities.diveTerminalVelocities) == "hash") {
      var ave=0;
      var count=0;
      var sum=0;
      var dTV=b.velocities.diveTerminalVelocities;
      var sin=0; var deltaV_kt=0; var factor=0; 
      foreach (k; keys (dTV) ) {
        dTV[k].airspeed_kt = checkRangeHash (dTV[k], "airspeed_kt", 0, nil, nil );
        
        dTV[k].vertical_speed_fps = checkRangeHash (dTV[k], "vertical_speed_fps", -100000, 0, nil );
        
        if ( dTV[k].airspeed_kt!= nil and dTV[k].vertical_speed_fps != nil ){
          dTV[k].airspeed_fps= dTV[k].airspeed_kt * knots2fps;
          sin=math.abs(dTV[k].vertical_speed_fps/dTV[k].airspeed_fps);
          deltaV_kt= dTV[k].airspeed_kt  - b.velocities.attackSpeed_kt;
          factor= deltaV_kt/sin;
          sum+=factor;
          count+=1;      
        } else {
            dTV[k].airspeed_fps= nil; 
        }
      } 
      if (count>0) {
        ave=sum/count;
        b.velocities.diveTerminalVelocityFactor=ave;
      } else {
        b.velocities.diveTerminalVelocityFactor=700; #average of Camel & Zero values, so a good typical value        
      }  
    }
  
    if (contains (b.velocities, "climbTerminalVelocities") and typeof (b.velocities.climbTerminalVelocities) == "hash") {
      var ave=0;
      var count=0;
      var sum=0;
      var cTV=b.velocities.climbTerminalVelocities;
      var sin=0; var deltaV_kt=0; var factor=0; 
      foreach (k; keys (cTV) ) {
        cTV[k].airspeed_kt = checkRangeHash (cTV[k], "airspeed_kt", 0, nil, nil );
        
        cTV[k].vertical_speed_fps = checkRangeHash (cTV[k], "vertical_speed_fps", 0, nil, nil );
        
        if ( cTV[k].airspeed_kt!= nil and cTV[k].vertical_speed_fps != nil ){
          cTV[k].airspeed_fps= cTV[k].airspeed_kt * knots2fps;
          sin=math.abs(cTV[k].vertical_speed_fps/cTV[k].airspeed_fps);
          deltaV_kt= b.velocities.attackSpeed_kt - cTV[k].airspeed_kt;
          factor= deltaV_kt/sin;
          sum+=factor;
          count+=1;
        } else {
            cTV[k].airspeed_fps= nil; 
        }       
      } 
      if (count>0) {
        ave=sum/count;
        b.velocities.climbTerminalVelocityFactor=ave;
      } else {
        b.velocities.climbTerminalVelocityFactor=750; #average of Camel & Zero values, so a good typical value        
      }  
    }
  } 
  ##damage sanity checking
  if (contains (b, "vulnerabilities") and typeof (b.vulnerabilities) == "hash") {  
    if (b.vulnerabilities.damageVulnerability<=0) b.vulnerabilities.damageVulnerability = 1;
    b.vulnerabilities.engineDamageVulnerability_percent = checkRange (b.vulnerabilities.engineDamageVulnerability_percent, 0, 100, 1 );
    b.vulnerabilities.fireVulnerability_percent = checkRange (b.vulnerabilities.fireVulnerability_percent, -1, 100, 20 );             
    b.vulnerabilities.fireDamageRate_percentpersecond = checkRange (b.vulnerabilities.fireDamageRate_percentpersecond, 0, 100, 1 );
    b.vulnerabilities.fireExtinguishMaxTime_seconds = checkRange (b.vulnerabilities.fireExtinguishMaxTime_seconds, 0, nil, 3600 );
    b.vulnerabilities.fireExtinguishSuccess_percentage = checkRange ( b.vulnerabilities.fireExtinguishSuccess_percentage, 0, 100, 10 );
    b.vulnerabilities.explosiveMass_kg = checkRange ( b.vulnerabilities.explosiveMass_kg, 0, 10000000, 1000 );
  }
  
  if (contains (b, "attacks") and typeof (b.attacks) == "hash") {
    ##attacks sanity checking
    if (b.attacks.minDistance_m < 0) b.attacks.maxDistance_m=100;
    if (b.attacks.maxDistance_m < b.attacks.minDistance_m ) b.attacks.maxDistance_m=2*b.attacks.minDistance_m;
    if (b.attacks.rollMin_deg == nil ) b.attacks.rollMin_deg=30;  
    if (b.attacks.rollMin_deg < 0) b.attacks.rollMin_deg=100;  
    if (b.attacks.rollMax_deg == nil ) b.attacks.rollMax_deg=80;
    if (b.attacks.rollMax_deg < b.attacks.rollMax_deg) b.attacks.rollMax_deg=b.attacks.rollMin_deg + 30;
    b.attacks.rollRateMax_degpersec = checkRangeHash ( b.attacks, "rollRateMax_degpersec", 1, 720, 45 );

    if (b.attacks.climbPower == nil ) b.attacks.climbPower=2000;
    if (b.attacks.climbPower < 0) b.attacks.climbPower=2000;    
    if (b.attacks.divePower == nil ) b.attacks.divePower=4000;
    if (b.attacks.divePower < 0) b.attacks.divePower=4000;       
    if (b.attacks.attackCheckTime_sec == nil ) b.attacks.attackCheckTime_sec=15;
    if (b.attacks.attackCheckTime_sec < 0.1) b.attacks.attackCheckTime_sec=0.1;
    if (b.attacks.attackCheckTimeEngaged_sec == nil ) b.attacks.attackCheckTimeEngaged_sec=1.25;
    if (b.attacks.attackCheckTimeEngaged_sec < 0.1) b.attacks.attackCheckTimeEngaged_sec=0.1;
  }
  
  ##weapons sanity checking
  if (contains(b, "weapons") and typeof (b.weapons) == "hash") {
    var n=0;      
      foreach (elem ; keys(b.weapons)) {
        n+=1;
        if (b.weapons[elem].name == nil ) b.weapons[elem].name="Weapon " ~ n;
        if (b.weapons[elem].maxDamage_percent == nil ) b.weapons[elem].maxDamage_percent=5;
        if (b.weapons[elem].maxDamage_percent < 0) b.weapons[elem].maxDamage_percent=0;
        if (b.weapons[elem].maxDamage_percent > 100) b.weapons[elem].maxDamage_percent=100;                         
        if (b.weapons[elem].maxDamageDistance_m == nil ) b.weapons[elem].maxDamageDistance_m=500;
        if (b.weapons[elem].maxDamage_percent <= 0) b.weapons[elem].maxDamageDistance_m=1;
        if (b.weapons[elem].weaponAngle_deg.heading == nil ) b.weapons[elem].weaponAngle_deg.heading=0;
        if (b.weapons[elem].weaponAngle_deg.elevation == nil ) b.weapons[elem].weaponAngle_deg.elevation=0;
        if (b.weapons[elem].weaponOffset_m.x == nil ) b.weapons[elem].weaponOffset_m.x=0;
        if (b.weapons[elem].weaponOffset_m.y == nil ) b.weapons[elem].weaponOffset_m.y=0;  
        if (b.weapons[elem].weaponOffset_m.z == nil ) b.weapons[elem].weaponOffset_m.z=0;
        
        if (!contains(b.weapons[elem], "weaponSize_m"))  
           b.weapons[elem].weaponSize_m = {start:nil, end:nil};
           
        if (b.weapons[elem].weaponSize_m.start == nil 
              or b.weapons[elem].weaponSize_m.start <=0 ) b.weapons[elem].weaponSize_m.start=0.07;
        if (b.weapons[elem].weaponSize_m.end == nil 
              or b.weapons[elem].weaponSize_m.end <=0 ) b.weapons[elem].weaponSize_m.end=0.05;  
      }  
  }  
  
  if (contains (b, "damageLiveries") and typeof (b.damageLiveries) == "hash") {                            
    b.damageLiveries.count = size (b.damageLiveries.damageLivery) ;
  }
  
  b["stores"]={};
  b.stores["fuel"]=1;
  b.stores["weapons"]={};
  b.stores["messages"]={};
  b.stores["messages"]["unreadymessageposted"]=0;
  b.stores["messages"]["readymessageposted"]=1;

  
  
  #the object has stored the node telling where to store itself on the 
  # property tree as b.objectNodeName.  This creates "/bombable/attributes"
  # under the nodename & saves these values there.  
  b.objectNode.getNode("bombable/attributes",1).setValues( b );
  
  #for now we are saving the attributes hash to the property tree and 
  # then also under attributes[myNodeName].  Many of the functions above 
  # still get certain
  # attributes values from the property tree.  However it is far better for 
  # performance to simply store the values in a local variable.
  # In future for performance reasons we might just save it under local
  # variable attributes[myNodeName] and not in the property tree at all, unless
  # something needs to be made globally available to change at runtime.  
  attributes[b.objectNodeName]=b;
  var myNodeName=b.objectNodeName;
  stores.fillWeapons(myNodeName,1);
  stores.fillFuel(myNodeName,1);
}

#################################################
# update_m_per_deg_latlon_loop
#  loop to periodically update the m_per_deg_lat & lon 
# 
var update_m_per_deg_latlon = func  {

  alat_deg=getprop ("/position/latitude-deg");
  var aLat_rad=alat_deg/rad2degrees;  
  m_per_deg_lat= 111699.7 - 1132.978 * math.cos (aLat_rad);
  m_per_deg_lon= 111321.5 * math.cos (aLat_rad);
  
  #TODO: there is really no reason to save these to the property tree, they could
  #just be bombable general variables 
  #setprop ("/bombable/sharedconstants/m_per_deg_lat", m_per_deg_lat);
  #setprop ("/bombable/sharedconstants/m_per_deg_lon", m_per_deg_lon);
}

#################################################
# update_m_per_deg_latlon_loop
#  loop to periodically update the m_per_deg_lat & lon 
# 
var update_m_per_deg_latlon_loop = func (id) {
  var loopid = getprop("/bombable/loopids/update_m_per_deg_latlon-loopid"); 
	id == loopid or return;
  #debprint ("update_m_per_deg_latlon_loop starting");
  settimer ( func { update_m_per_deg_latlon_loop(id)}, 63.2345);

  update_m_per_deg_latlon();
  
}  

##########################################
#setMaxLatLon
#

var setMaxLatLon = func (myNodeName, damageDetectDistance_m){

  #m_per_deg_lat = getprop ("/bombable/sharedconstants/m_per_deg_lat");
  #m_per_deg_lon = getprop ("/bombable/sharedconstants/m_per_deg_lon");

  if ( m_per_deg_lat == nil or m_per_deg_lon == nil ) {
  
    update_m_per_deg_latlon();
    #m_per_deg_lat = getprop ("/bombable/sharedconstants/m_per_deg_lat");
    #m_per_deg_lon = getprop ("/bombable/sharedconstants/m_per_deg_lon");
  }  


  maxLat=  damageDetectDistance_m / m_per_deg_lat;
  maxLon=  damageDetectDistance_m / m_per_deg_lon; 
	
	debprint ("Bombable: maxLat = ", maxLat, " maxLon = ", maxLon);
	
  #put these in nodes also so they can be easily updated by an external
  #routine or timer
	#props.globals.getNode(""~myNodeName~"/bombable/attributes/dimensions/maxLat",1).setDoubleValue( maxLat);
	
	attributes[myNodeName].dimensions.maxLat= maxLat;
	#props.globals.getNode(""~myNodeName~"/bombable/attributes/dimensions/maxLon",1).setDoubleValue( maxLon);
	
	attributes[myNodeName].dimensions.maxLon= maxLon;

}


var bombable_init = func (myNodeName="") {
  debprint ("Bombable: Delaying bombable_init . . . ", myNodeName);
  settimer (func {bombable_init_func(myNodeName);}, 35 + rand(),1);

}

#####################################################
#call to make an object bombable
#
# features/parameters are set by a bombableObject and
# a previous call to initialize (above)
var bombable_init_func = func(myNodeName) {
 

 #only allow initialization for ai & multiplayer objects
 # in FG 2.4.0 we're having trouble with strange(!?) init requests from
 # joysticks & the like  
 var init_allowed=0;
 if (find ("/ai/models/", myNodeName ) != -1 ) init_allowed=1;
 if (find ("/multiplayer/", myNodeName ) != -1 ) init_allowed=1;

 if (init_allowed!=1) {
   debprint ("Bombable: Attempt to initialize a Bombable subroutine on an object that is not AI or Multiplayer; aborting initialization. ", myNodeName);
   return;
 } 

  
 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 # if it 1 and we're trying to initialize, something has gone wrong and we abort with a message.  
 var inited= getprop(""~myNodeName~"/bombable/initializers/bombable-initialized");
 if (inited==1) {
   debprint ("Bombable: Attempt to re-initialize bombable_init when it has not been de-initialized; aborting re-initialization. ", myNodeName);
   return;
 } 
 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 setprop(""~myNodeName~"/bombable/initializers/bombable-initialized", 1);



	
  debprint ("Bombable: Starting to initialize for "~myNodeName);
  if (myNodeName=="" or myNodeName==nil) {
    myNodeName=cmdarg().getPath();
    debprint ("Bombable: myNodeName blank, re-reading: "~myNodeName);
  }
    
  var node = props.globals.getNode (""~myNodeName);
  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  #var alts = b.getNode("altitudes").getValues();	
  #var dims = b.getNode("dimensions").getValues();
  #var vels = b.getNode("velocities").getValues();
     
  var alts = attributes[myNodeName].altitudes;	
  var dims = attributes[myNodeName].dimensions;
  var vels = attributes[myNodeName].velocities; 

 	type=node.getName();
	
  #we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	loopid=inc_loopid(myNodeName, "fire");
 	
  setMaxLatLon(myNodeName, dims.damageRadius_m+200);

  var listenerids=[];
  	
  #impactReporters is the list of (theoretically) all places in the property
  #tree where impacts/collisions will be reported.  It is set in the main
  #bombableIinit function	
  foreach (var i; bombable.impactReporters) {   
    #debprint ("i: " , i); 		
	  listenerid=setlistener(i, func ( changedImpactReporterNode ) { 
      test_impact( changedImpactReporterNode, myNodeName ); });
    append(listenerids, listenerid);
  
  }
	

	#start the loop to check for fire damage
	settimer(func{fire_loop(loopid,myNodeName);},5.2 + rand());
	
	debprint ("Bombable: Effect *bombable* loaded for "~myNodeName~" loopid="~ loopid);


    #what to do when re-set is selected
  setlistener("/sim/signals/reinit", func {
    resetBombableDamageFuelWeapons (myNodeName);    
    if (type=="multiplayer") mp_send_damage(myNodeName, 0);
    debprint ("Bombable: Damage level and smoke reset for "~ myNodeName);
  });
  
  
  if (type=="multiplayer") {
    
    #set up the mpreceive listener.  The final 0, 0) makes it
    # trigger only when the location has *changed*.  This is necessary
    # because the location is written to each frame, but only changed
    # occasionally.                 
    listenerid=setlistener(myNodeName~MP_message_pp,mpreceive, 0, 0);
    append(listenerids, listenerid);
    
    #We're using a listener rather than the settimer now, so the line below is removed
    #settimer (func {mpreceive(myNodeName,loopid)}, mpTimeDelayReceive);
    debprint ("Bombable: Setup mpreceive for ", myNodeName);
             
  }
  
  
  
  props.globals.getNode(""~myNodeName~"/bombable/listenerids",1).setValues({"listenerids":listenerids });
  
	
	return;
	
	
}

var ground_init = func (myNodeName="") {

  debprint ("Bombable: Delaying ground_init . . . ", myNodeName);
  settimer (func {bombable.ground_init_func(myNodeName);}, 45 + rand(),1);

}

#####################################################
# Call to make your object stay on the ground, or at a constant
# distance above ground level--like a jeep or tank that drives along 
# the ground, or an aircraft that moves along at, say, 500 ft AGL.  
# The altitide will be continually readjusted
# as the object (set up as, say, and AI ship or aircraft moves.
# In addition, for "ships" the pitch will change to (roughly) match 
# when going up or downhill.
#
var ground_init_func = func( myNodeName ) {
 #return;
 #only allow initialization for ai & multiplayer objects
 # in FG 2.4.0 we're having trouble with strange(!?) init requests from
 # joysticks & the like  
 var init_allowed=0;
 if (find ("/ai/models/", myNodeName ) != -1 ) init_allowed=1;
 if (find ("/multiplayer/", myNodeName ) != -1 ) init_allowed=1;

 if (init_allowed!=1) {
   debprint ("Bombable: Attempt to initialize a Bombable subroutine on an object that is not AI or Multiplayer; aborting initialization. ", myNodeName);
   return;
 } 

 var node = props.globals.getNode(myNodeName);
 type=node.getName();
  
 #don't even try to do this to multiplayer aircraft
 if (type == "multiplayer") return;


 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 # if it 1 and we're trying to initialize, something has gone wrong and we abort with a message.  
 var inited= getprop(""~myNodeName~"/bombable/initializers/ground-initialized");
 if (inited==1) {
   debprint ("Bombable: Attempt to re-initialize ground_init when it has not been de-initialized; aborting re-initialization. ", myNodeName);
   return;
 } 
 

 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 setprop(""~myNodeName~"/bombable/initializers/ground-initialized", 1);



  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  #alts= b.getNode("altitudes").getValues();
  alts=attributes[myNodeName].altitudes; 
      	
				
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid(myNodeName, "ground");
	  
	# Add some useful nodes
	
	
	
  #get the object's initial altitude
	var lat = getprop(""~myNodeName~"/position/latitude-deg");
  var lon = getprop(""~myNodeName~"/position/longitude-deg");
  var alt=elev (lat, lon);
  
  #Do some checking for the ground_loop function so we don't always have
  #to check this in that function
  #damageAltAdd is the (maximum) amount the object will descend 
  #when it is damaged.
  
	settimer(func { ground_loop(loopid, myNodeName); }, 4.1 + rand());
	
	debprint ("Bombable: Effect *maintain altitude above ground level* loaded for "~ myNodeName);
  # altitude adjustment=", alts.wheelsOnGroundAGL_ft, " max drop/fall when damaged=",
  # damageAltAdd, " loopid=", loopid);

}

var location_init = func (myNodeName="") {

  debprint ("Bombable: Delaying location_init . . . ", myNodeName);
  settimer (func {bombable.location_init_func(myNodeName);}, 50 + rand(),1);

}

#####################################################
# Call to make your object keep its location even after a re-init
# (file/reset).  For instance a fleet of tanks, cars, or ships
# will keep its position after the reset rather than returning
# to their initial position.'
#
# Put this nasal code in your object's load:
#      bombable.location_init (cmdarg().getPath())

var location_init_func = func(myNodeName) {
 #return;
 
 #only allow initialization for ai & multiplayer objects
 # in FG 2.4.0 we're having trouble with strange(!?) init requests from
 # joysticks & the like  
 var init_allowed=0;
 if (find ("/ai/models/", myNodeName ) != -1 ) init_allowed=1;
 if (find ("/multiplayer/", myNodeName ) != -1 ) init_allowed=1;

 if (init_allowed!=1) {
   debprint ("Bombable: Attempt to initialize a Bombable subroutine on an object that is not AI or Multiplayer; aborting initialization. ", myNodeName);
   return;
 } 

 var node = props.globals.getNode(myNodeName);
 type=node.getName();
 #don't even try to do this to multiplayer aircraft
 if (type == "multiplayer") return;

	
 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 # if it 1 and we're trying to initialize, something has gone wrong and we abort with a message.  
 var inited= getprop(""~myNodeName~"/bombable/initializers/location-initialized");
 if (inited==1) {
   debprint ("Bombable: Attempt to re-initialize location_init when it has not been de-initialized; aborting re-initialization. ", myNodeName);
   return;
 } 
 # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
 setprop(""~myNodeName~"/bombable/initializers/location-initialized", 1);

	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid(myNodeName, "location");
	
	
	settimer(func { location_loop(loopid, myNodeName); }, 15.15 + rand());

  debprint ("Bombable: Effect *relocate after reset* loaded for "~ myNodeName~ " loopid="~ loopid);

}

var attack_init = func (myNodeName="") {

  debprint ("Bombable: Delaying attack_init . . . ", myNodeName);
  settimer (func {bombable.attack_init_func(myNodeName);}, 55 + rand(),1 );

}

##########################################################
# Call to make your object turn & attack the main aircraft
#
# Put this nasal code in your object's load:
#      bombable.attack_init (cmdarg().getPath())

var attack_init_func = func(myNodeName) {
   #return;
   #only allow initialization for ai & multiplayer objects
   # in FG 2.4.0 we're having trouble with strange(!?) init requests from
   # joysticks & the like  
   var init_allowed=0;
   if (find ("/ai/models/", myNodeName ) != -1 ) init_allowed=1;
   if (find ("/multiplayer/", myNodeName ) != -1 ) init_allowed=1;
  
   if (init_allowed!=1) {
     debprint ("Bombable: Attempt to initialize a Bombable subroutine on an object that is not AI or Multiplayer; aborting initialization. ", myNodeName);
     return;
   } 

   var node = props.globals.getNode(myNodeName);
   type=node.getName();
   #don't even try to do this to multiplayer aircraft
   if (type == "multiplayer") {
       debprint ("Bombable: Not initializing attack for multiplayer aircraft; exiting . . . ");
       return;
   }


   # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
   # if it 1 and we're trying to initialize, something has gone wrong and we abort with a message.  
   var inited= getprop(""~myNodeName~"/bombable/initializers/attack-initialized");
   if (inited==1) {
     debprint ("Bombable: Attempt to re-initialize attack_init when it has not been de-initialized; aborting re-initialization. ", myNodeName);
     return;
   } 
   # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
   setprop(""~myNodeName~"/bombable/initializers/attack-initialized", 1);

	
	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid (myNodeName, "attack");
  
  #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
  #var atts= b.getNode("attacks").getValues();
  atts=attributes[myNodeName].attacks;

	attackCheckTime=atts.attackCheckTime_sec;
	if (attackCheckTime==nil or attackCheckTime<0.5)attackCheckTime=0.5;
  
  # Set an individual pilot weapons ability, -1 to 1, with 0 being average
  pilotAbility = math.pow (rand(), 1.5) ;
  if (rand()>.5) pilotAbility=-pilotAbility;
  setprop(""~myNodeName~"/bombable/attack-pilot-ability", pilotAbility);
  
	settimer(func { attack_loop(loopid, myNodeName,attackCheckTime); }, attackCheckTime + rand());
	
  #start the speed adjust loop.  Adjust speed up/down depending on climbing/
  # diving, or level flight; only for AI aircraft.
  if (type == "aircraft") {
    		
    	var loopid=inc_loopid (myNodeName, "speed-adjust");
    	settimer (func { speed_adjust_loop ( loopid, myNodeName, .3 + rand()/30); }, 12+rand());
  }  	

  debprint ("Bombable: Effect *attack* loaded for "~ myNodeName~ " loopid="~ loopid);

}

#################################################
# weaponsOrientationPositionUpdate_loop
# to update the position/angle of weapons attached
# to AI aircraft.  Use for visual weapons effects
# now but could be used for weapons aim etc in the future.
# 

var weaponsOrientationPositionUpdate_loop = func (id, myNodeName) {


          #var myNode=changedNode.getParent().getParent();
          #var myNodeName=myNode.getPath();
          
          var loopid = getprop(""~myNodeName~"/bombable/loopids/weaponsOrientation-loopid"); 
          id == loopid or return;
          
          settimer (func { weaponsOrientationPositionUpdate_loop (id, myNodeName)}, .16 + rand()/50);
          
          #no need to do this if any of these are turned off
          # though we may update weapons_loop to rely on these numbers as well          
          if (! getprop("/bombable/fire-particles/ai-weapon-firing")
                or ! getprop ( trigger1_pp~"ai-weapon-fire-visual"~trigger2_pp)
                or ! getprop(bomb_menu_pp~"bombable-enabled") 
                ) return;
          
          #debprint ("weapsOrientatationPos_loop calcs starting");
          #var weaps = props.globals.getNode(myNodeName~"/bombable/attributes/weapons").getValues();
          
          weaps=attributes[myNodeName].weapons; 
                              
          #debprint ("ist: ", myNodeName, " node: ",listenedNode.getName(), " weap:", 
          # weaps[elem].weaponAngle_deg.elevation);
           
          foreach (elem;keys (weaps) ) {
           
           setprop(myNodeName ~ "/" ~elem~"/orientation/pitch-deg", 
              getprop(myNodeName~"/orientation/pitch-deg")+weaps[elem].weaponAngle_deg.elevation);
                            
           setprop(myNodeName ~ "/" ~elem~"/orientation/true-heading-deg", 
              getprop(myNodeName~"/orientation/true-heading-deg")+ weaps[elem].weaponAngle_deg.heading);

           setprop(myNodeName ~ "/" ~elem~"/position/altitude-ft", 
              getprop(myNodeName~"/position/altitude-ft")+weaps[elem].weaponOffset_m.z*.3048);                            

           setprop(myNodeName ~ "/" ~elem~"/position/latitude-deg", 
              getprop(myNodeName~"/position/latitude-deg") ); #todo: add the x & y offsets; they'll have to be rotated and then converted to lat/lon and that's going to be slow . . .                             

           setprop(myNodeName ~ "/" ~elem~"/position/longitude-deg", 
              getprop(myNodeName~"/position/longitude-deg")); #todo: add the x & y offsets  
          }                              
        
}

#####################################
# weaponsTrigger_listener
# Listen when the remote MP aircraft triggers weapons and un-triggers them,
# and show our local visual weapons effect whenever they are triggered
# Todo: Make the visual weapons effect stop triggering when the remote MP 
# aircraft is out of ammo
#
var weaponsTrigger_listener = func (changedNode,listenedNode){

  #for now there is only one trigger for ALL AI visual weapons
  # so we just turn it on/off depending on the trigger value
  # TODO: Since there are possibly multiple triggers there is the possibility
  # of the MP aircraft holding both trigger1 and trigger2 and then
  # releasing only trigger2, which will turn off the visual effect 
  # for all weapons here.  It would take some logic to fix that little flaw.  
  # TODO: there is only one visual effect & one trigger for EVERYTHING for now, so setting the
  # trigger=1 turns on all weapons for all AI/Multiplayer aircraft.
  # Making it turn on/off individually per weapon per aircraft is going to be a 
  # fair-sized job.        
  debprint ("Bombable: WeaponsTrigger_listener: ",changedNode.getValue(), " ", changedNode.getPath());           
  if ( changedNode.getValue()) {
    setprop("/bombable/fire-particles/ai-weapon-firing",1);
  } else {
    setprop("/bombable/fire-particles/ai-weapon-firing",0); 
  }

}

var weapons_init = func (myNodeName="") {

  debprint ("Bombable: Delaying weapons_init . . . ", myNodeName);
  settimer (func {weapons_init_func(myNodeName);}, 60 + rand(),1);

}

############################################################
# Call to make your object fire weapons at the main aircraft
# If the main aircraft gets in the 'fire zone' directly ahead
# of the weapons you set up, the main aircraft will be damaged
#
# Put this nasal code in your object's load:
#      bombable.weapons_init (cmdarg().getPath())

var weapons_init_func = func(myNodeName) {
   #return;
   myNode=props.globals.getNode(myNodeName);
   type=myNode.getName();
   
   #only allow initialization for ai & multiplayer objects
   # in FG 2.4.0 we're having trouble with strange(!?) init requests from
   # joysticks & the like  
   var init_allowed=0;
   if (find ("/ai/models/", myNodeName ) != -1 ) init_allowed=1;
   if (find ("/multiplayer/", myNodeName ) != -1 ) init_allowed=1;
  
   if (init_allowed!=1) {
     debprint ("Bombable: Attempt to initialize a Bombable subroutine on an object that is not AI or Multiplayer; aborting initialization. ", myNodeName);
     return;
   } 
   
   
   
   #don't do this for multiplayer . . . 
   #if (type=="multiplayer") return;
   # oops . . . now we ARE doing part of this for MP, so they can have the weapons visual effect   

   # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
   # if it 1 and we're trying to initialize, something has gone wrong and we abort with a message.  
   var inited= getprop(""~myNodeName~"/bombable/initializers/weapons-initialized");
   if (inited==1) {
     debprint ("Bombable: Attempt to re-initialize weapons_init when it has not been de-initialized; aborting re-initialization. ", myNodeName);
     return;
   } 
   
   #don't do this if the 'weapons' attributes are not included
   #var b = props.globals.getNode (""~myNodeName~"/bombable/attributes");
   var weapsSuccess=1;
   if (!contains (attributes[myNodeName], "weapons")) { debprint ("no attributes.weapons, exiting"); weapsSuccess=0;} 
   else { 
      weaps = attributes[myNodeName].weapons;
      if (weaps == nil or typeof(weaps) != "hash") {debprint ("attributes.weapons not a hash"); bSuccess=0; }
   }
   
   if (weapsSuccess==0) return;   #alternatively we could implement a fake/basic armament here
                              #for any MP aircraft that don't have a bombable section.
     
   
   # set to 1 if initialized and 0 when de-inited. Nil if never before inited.
   setprop(""~myNodeName~"/bombable/initializers/weapons-initialized", 1);
 
   #listenerids=[];  
   #listenNodeName=""~myNodeName~"/orientation/pitch-deg";
   #listenNode=props.globals.getNode(listenNodeName);  
   #listenerid= setlistener (listenNode, weapsOrientationPositionUpdate );      

   #OK, FG doesn't seem to give any way to position or rotate a 
   # particlesystem xml model in relation to a submodel.  So we're going to do it by hand . . . 
   #       
   #a listener would seem better/more appropriate here, but in FG 2.4.0, listeners
   # don't seem to work on AI aircraft position or orientation nodes???
   # Anyway the timer loop seems to work well enough and probably has far less
   # effect on framerate         
   var loopid=inc_loopid (myNodeName, "weaponsOrientation"); 
   settimer (func { weaponsOrientationPositionUpdate_loop(loopid, myNodeName)} , 3 +rand());
      
   foreach (elem;keys (weaps) ) put_tied_weapon(myNodeName, elem,
        weaps[elem].weaponSize_m.start, weaps[elem].weaponSize_m.end,
        "AI/Aircraft/Fire-Particles/projectile-tracer.xml");
   debprint ("Weaps: ", myNodeName, " initialized ");
   #append(listenerids, listenerid);
   #props.globals.getNode(""~myNodeName~"/bombable/weapons/listenerids",1).setValues({listenerids: listenerids});

  props.globals.getNode(""~myNodeName~"/bombable/weapons/listenerids",1);  
  #do the visual weapons effect setup for multiplayer . . .
   
  if (type=="multiplayer") {    

      debprint ("Bombable: Setting up MP weapons for ", myNodeName, " type ", type);
      
      #setup alias for remote weapon trigger(s) and a listener to trigger 
      # our local weapons visual effect whenever it a trigger is set to 1
      # sets /ai/models/multiplayer[X]/controls/armament/triggerN (for n=0..10)
      # as alias of the multiplayer generic int0..10 properties & then sets
      # up a listener for each of them to turn the visual weapons effect on
      # whenever a trigger is pulled.                              
      listenerids=[];  
      for (n=0;n<10;n+=1) {

        var genericintNum=n+10;
        
        # OK, the idea of an alias sounded great but apparently listeners don't work on aliases (???)
        # if (n==0) var appendnum=""; else var appendnum = n;  
        # myNode.getNode("controls/armament/trigger"~appendnum, 1).
        # listenNodeName=""~myNodeName~"/controls/armament/trigger";          
        # alias(myNode.getNode("sim/multiplay/generic/int["~genericintNum~"]"));
        # debprint ("Bombable: Setting up listener for ", listenNodeName ~ appendnum);
        # listenerid= setlistener ( listenNodeName ~ appendnum, weaponsTrigger_listener, 1, 0 );  #final 0 makes it listen only when the value is changed            
        
        #So we're doing it the basic way: just listen directly to the generic/int node, 10-19:
        listenerid= setlistener (""~myNodeName~"/sim/multiplay/generic/int["~genericintNum~"]", weaponsTrigger_listener, 1, 0 );  #final 0 makes it listen only when the listened value is changed; for MP it is written every frame but only changed occasionally                                                        
        append(listenerids, listenerid);
      }
      props.globals.getNode(""~myNodeName~"/bombable/weapons/listenerids",1).setValues({listenerids: listenerids});
  }        
  #don't do this bit (AI logic for automatic firing of weapons) for multiplayer, only for AI aircraft . . . 
  if (type!="multiplayer") {  
      #overall height & width of main aircraft in meters  
      # TODO: Obviously, this needs to be set per aircraft in an XML file, along with aircraft
      # specific damage vulnerability etc.         
      var mainAircraftSize_m = { vert : 4, horz : 8 };
      
      # Set an individual pilot weapons ability, -1 to 1, with 0 being average
      pilotAbility = math.pow (rand(), 1.5) ;
      if (rand()>.5) pilotAbility=-pilotAbility;
      setprop(""~myNodeName~"/bombable/weapons-pilot-ability", pilotAbility);
                  
      #settimer (  func { weapons_loop (myNodeName, "", vertAngle_deg, horzAngle_deg, atts.maxDamageDistance_m, atts.maxDamage_percent)}, 5);  
  
    	#we increment this each time we are inited or de-inited
    	#when the loopid is changed it kills the timer loops that have that id
      var loopid=inc_loopid (myNodeName, "weapons");    
      
      settimer (  func { weapons_loop (loopid, myNodeName, "", mainAircraftSize_m)}, 5 + rand());
  } 
                       
  debprint ("Bombable: Effect *weapons* loaded for ", myNodeName);
  
  
}


#####################################################
#unload function (delete/destructor) for initialize
#
#typical usage:
#<PropertyList>
#...
# <nasal>
#...
#  <unload>
#      bombable.initialize_del (cmdarg().getPath(), id);
#  </unload
# </nasal>  
#</PropertyList>
# Note: As of Bombable 3.0m, id is not used for anything
# (listenerids are stored as nodes, which works much better)

var initialize_del = func(myNodeName, id="") {
	   
  #set this to 0/false when de-inited 
  setprop(""~myNodeName~"/bombable/initializers/attributes-initialized", 0);	
	debprint ("Bombable: Effect initialize unloaded for "~ myNodeName );
	
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
#      bombable.bombable_del (cmdarg().getPath(), id);
#  </unload
# </nasal>  
#</PropertyList>
# Note: As of Bombable 3.0m, id is not used for anything
# (listenerids are stored as nodes, which works much better)

var bombable_del = func(myNodeName, id="") {
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid(myNodeName, "bomb");
	var loopid2=inc_loopid(myNodeName, "fire");
	
	
	listids = props.globals.getNode(""~myNodeName~"/bombable/listenerids",1).getValues();
	
  #remove the listener to check for impact damage				
	if (listids!= nil and contains (listids, "listenerids")) { 
      foreach (k;listids.listenerids) { removelistener(k); }
      props.globals.getNode(""~myNodeName~"/bombable/listenerids",1).removeChildren();
  }
   
	
	#this loop will be killed when we increment loopid as well
	#settimer(func { fire_loop(loopid, myNodeName); }, 5.0+rand());
   
  #set this to 0/false when de-inited 
  setprop(""~myNodeName~"/bombable/initializers/bombable-initialized", 0);	
	debprint ("Bombable: Effect *bombable* unloaded for "~ myNodeName~ " loopid=", loopid, 
     " loopid2=", loopid2);
	

}

#####################################################
# del/destructor function for ground_init
# Put this nasal code in your object's unload:
#      bombable.bombable_del (cmdarg().getPath());
var ground_del = func(myNodeName) {
				
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid(myNodeName, "ground");

  #set this to 0/false when de-inited 
  setprop(""~myNodeName~"/bombable/initializers/ground-initialized", 0);	
	
	debprint ("Bombable: Effect *drive on ground* unloaded for "~ myNodeName~ " loopid="~ loopid);

	
}

#####################################################
# del/destructor for location_init
# Put this nasal code in your object's unload:
#      bombable.location_del (cmdarg().getPath());

var location_del = func(myNodeName) {
	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid(myNodeName, "location");
	
  #set this to 0/false when de-inited 
  setprop(""~myNodeName~"/bombable/initializers/location-initialized", 0);	

  debprint ("Bombable: Effect *relocate after reset* unloaded for "~ myNodeName~ " loopid="~ loopid);

}

#####################################################
# del/destructor for attack_init
# Put this nasal code in your object's unload:
#      bombable.location_del (cmdarg().getPath());

var attack_del = func(myNodeName) {
	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid(myNodeName, "attack");
	
  #set this to 0/false when de-inited 
  setprop(""~myNodeName~"/bombable/initializers/attack-initialized", 0);	

  debprint ("Bombable: Effect *attack* unloaded for "~ myNodeName~ " loopid="~ loopid);

}

#####################################################
# del/destructor for weapons_init
# Put this nasal code in your object's unload:
#      bombable.location_del (cmdarg().getPath());

var weapons_del = func(myNodeName) {
	
  #set this to 0/false when de-inited 
  setprop(""~myNodeName~"/bombable/initializers/weapons-initialized", 0);	
	
	#we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid = inc_loopid(myNodeName, "weapons");
	var loopid2 = inc_loopid(myNodeName, "weaponsOrientation");

  listids = props.globals.getNode(""~myNodeName~"/bombable/weapons/listenerids",1).getValues();

  #remove the listener to check for impact damage				
	if (listids!= nil and contains (listids, "listenerids")) { 
      foreach (k;listids.listenerids) { removelistener(k); }
  }
  props.globals.getNode(""~myNodeName~"/bombable/weapons/listenerids",1).removeChildren(); 
  

	

  debprint ("Bombable: Effect *weapons* unloaded for "~ myNodeName~ " weapons loopid="~ loopid ~
     " and weaponsOrientation loopid="~loopid2);

}


var countmsg=0;





###########################################################
#initializers
#

#Turn fire/smoke on globally for the fire-particles system.  
#As soon as a fire-particle model is placed it will
#start burning.  To stop it from burning, simply remove the model.
#You can turn off all smoke/fires globally by setting the trigger to false 


var broadcast = nil;
var Binary = nil;
var seq = 0;
var rad2degrees=180/math.pi;
var feet2meters=.3048;
var meters2feet=1/feet2meters;
var nmiles2meters=1852;
var meters2nmiles=1/nmiles2meters;
var knots2fps=1.68780986;
var fps2knots=1/knots2fps;
var grav_fpss=32.174;
var bomb_menu_pp="/bombable/menusettings/";
var bombable_settings_file=getprop("/sim/fg-home") ~ "/state/bombable-startup-settings.xml";  

var bomb_menuNum = -1; #we set this to -1 initially and then the FG menu number when it is assigned

var trigger1_pp= ""~bomb_menu_pp~"fire-particles/";
var trigger2_pp= "-trigger";
var burning_pp= "-burning";
var life1_pp= "/bombable/fire-particles/";
var life2_pp= "-life-sec";                                                       
var burntime1_pp= "/bombable/fire-particles/";
var burntime2_pp= "-burn-time";
var attributes_pp = "/bombable/attributes";
var vulnerabilities_pp = attributes_pp ~ "/vulnerabilities/";
var GF_damage_pp = vulnerabilities_pp ~ "gforce_damage/";
var GF_damage_menu_pp = bomb_menu_pp ~ "gforce_damage/";
     
var MP_share_pp = bomb_menu_pp~"/MP-share-events/";
var MP_broadcast_exists_pp = "/bombable/mp_broadcast_exists/";
var screenHProp = nil;

records.init();

var tipArgTarget=nil;  
var tipArgSelf=nil;
var currTimerTarget = 0;
var currTimerSelf = 0;

var lockNum=0;
var lockWaitTime=1;
var masterLockWaitTime=.3;
var crashListener = 0;

#set initial m_per_deg_lon & lat
var alat_deg=45;
var aLat_rad=alat_deg/rad2degrees;  
var m_per_deg_lat= 111699.7 - 1132.978 * math.cos (aLat_rad);
var m_per_deg_lon= 111321.5 * math.cos (aLat_rad);


#where we'll save the attributes for each AI object & the main aircraft, too
var attributes = {};

#List of nodes that listeners will use when checking for impact damage. 
#FG aircraft use a wide variety of nodes to report impact of armament
#So we try to check them all.  There is no real overhead to this as
#only the one(s) active with a particular aircraft will ever get any activity.
#This should make all aircraft in the CVS version of FG (as of Aug 2009),
#which have armament that reports an impact, work with bombable.nas AI
#objects.
#
var impactReporters= [  
      "ai/models/model-impact",  #this is the FG default reporter
      "sim/armament/weapons/impact",
      "sim/ai/aircraft/impact/bullet",                       
      "sim/ai/aircraft/impact/gun",
      "sim/ai/aircraft/impact/cannon",
      "sim/model/bo105/weapons/impact/MG",
      "sim/model/bo105/weapons/impact/HOT",
      "sim/ai/aircraft/impact/droptank",
      "sim/ai/aircraft/impact/bomb" 
    ];	


####################################
#Set up initial variables for the mpsend/receive/queue system
#     
#The location we use for exchanging the messages
# send at MP_message_pp and receive at myNodeName~MP_message_pp
# ie, "/ai/models/multiplayer[3]"~MP_message_pp
var MP_message_pp="/sim/multiplay/generic/string[9]";
var msgTable={};
#we'll make delaySend 2X delayReceive--should make message receipt more reliable
var mpTimeDelayReceive=.12409348; #delay between checking for mp messages in seconds
var mpTimeDelaySend=.25100234; #delay between sending messages.
var mpsendqueue=[];
settimer (func {mpprocesssendqueue()}, 5.2534241 + rand()); #wait 5 seconds before initial send; rand makes sure they aren't all exactly synchronized

#Add damage when aircraft is accelerated beyond reasonable bounds
var damageCheckTime=1 + rand()/10;  
settimer (func { damageCheck () }, 60.11); #wait 30 sec before first damage check because sometimes there is a very high transient g-force on initial startup
  
var bombableInit = func {


  debprint("Bombable: Initializing variables.");
  screenHProp = props.globals.getNode("/sim/startup/ysize");
  tipArgTarget = props.Node.new({ "dialog-name" : "PopTipTarget" });  
  tipArgSelf = props.Node.new({ "dialog-name" : "PopTipSelf" });
  
  if ( ! getprop("/sim/ai/enabled") ) {
            var msg = "Bombable: WARNING! The Bombable module is active, but you have disabled the 
            entire FlightGear AI system using --disable-ai-models.  You will not be able to see 
            any AI or Multiplayer objects or use Bombable.  To fix this problem, remove 
            --disable-ai-models from your command line (or check/un-check the appropriate item in 
            your FlightGear startup 
            manager) and restart.";
            print (msg);
            #selfStatusPopupTip (msg, 10 );
  }         

  
  #read any existing bombable-startup-settings.xml  file if it exists
  # getprop("/sim/fg-home") = fg-home directory   
  
  #for some reason this isn't work; trying a 5 sec delay to 
  # see if that fixes it.  Something is maybe coming along
  # afterward an overwriting the values?      
  #settimer (setupBombableMenu, 5.12);
  setupBombableMenu();
  
	#these are for the "mothership" not the AI or MP objects
  #setprop("/bombable/fire-particles/fire-trigger", 0);
	#setprop("/bombable/attributes/damage", 0);
	
  # Add some useful nodes
  
  setprop ("/bombable/fire-particles/smoke-startsize", 11.0);
  setprop ("/bombable/fire-particles/smoke-endsize", 50.0);
  setprop ("/bombable/fire-particles/smoke-startsize-small", 6.5);
  setprop ("/bombable/fire-particles/smoke-endsize-small", 40);
  
  setprop ("/bombable/fire-particles/smoke-startsize-very-small", .316);
  setprop ("/bombable/fire-particles/smoke-endsize-very-small", 21);
  
  setprop ("/bombable/fire-particles/smoke-startsize-large", 26.0);
  setprop ("/bombable/fire-particles/smoke-endsize-large", 150.0);
  setprop ("/bombable/fire-particles/flack-startsize", 0.25);
  setprop ("/bombable/fire-particles/flack-endsize", 1.0);
  
  props.globals.getNode(bomb_menu_pp ~ "fire-particles/fire-trigger", 1).setBoolValue(1);
  #props.globals.getNode(bomb_menu_pp ~ "fire-particles/flack-trigger", 1).setBoolValue(0);

  props.globals.getNode("/bombable/attributes/damage", 1).setDoubleValue(0.0);

 	#turn on the loop to occasionally re-calc the m_per_deg lat & lon
 	# must be done before setMaxLatLon 	
	var loopid=inc_loopid("", "update_m_per_deg_latlon");
	settimer (func { update_m_per_deg_latlon_loop(loopid);}, 5.5435);	

  #sets max lat & lon for test_impact for main aircraft
  settimer (func { setMaxLatLon("", 500);}, 6.2398471);

  
  #this is zero if no AI or MP models have impact detection loaded, and > 0 otherwise
  var numModelImpactListeners=0;
  
  #adds the main aircraft to the impact report detection list
  foreach (var i; bombable.impactReporters) {   
  #debprint ("i: " , i); 		
	  listenerid=setlistener(i, func ( changedImpactReporterNode ) { 
      test_impact( changedImpactReporterNode, "" ); });
      #append(listenerids, listenerid);
  
  }
  

	
	#if (getprop (""~bomb_menu_pp~"debug") == nil ) {
	#  setprop (bomb_menu_save_lock, 1); #save_lock prevents this change from being written to the menu save file
  #	  props.globals.getNode(bomb_menu_pp~"debug", 1).setBoolValue(0);
  #	setprop (bomb_menu_save_lock, 0);
  #}	
	
  #turn on debug flag (for testing)
 	#  setprop (bomb_menu_save_lock, 1); #save_lock prevents this change from being written to the menu save file
	#props.globals.getNode(bomb_menu_pp~, 1).setBoolValue(1);
 	#  setprop (bomb_menu_save_lock, 0); #save_lock prevents this change from being written to the menu save file
	
  #set attributes for main aircraft
	attributesSet=getprop (""~attributes_pp~"/attrbitues_set");	
  if (attributesSet==nil or ! attributesSet ) setAttributes ();
  
  
  #we increment this each time we are inited or de-inited
	#when the loopid is changed it kills the timer loops that have that id
	var loopid=inc_loopid("", "fire");
  settimer(func{fire_loop(loopid,"");},5.04 + rand());


  
  #what to do when re-set is selected
  setlistener("/sim/signals/reinit", func {

    reset_damage_fires ();
    #for some reason this isn't work; trying a 5 sec delay to 
    # see if that fixes it    
    #settimer (setupBombableMenu, 5.32);
    setupBombableMenu();
     
  });
  
  
  # action to take when main aircraft crashes (or un-crashes)
  setlistener("/sim/crashed", func {
    if (getprop("/sim/crashed")) {
    
      mainAC_add_damage(1,1, "crash", "You crashed!");   #adds the damage to the main aircraft
        
      debprint ("Bombable: You crashed - on fire and damage set to 100%");
      
      #experimental/doesn't quite work right yet
      #aircraftCrash(""); #Experimental!
  
    } else {
    
       debprint ("Bombable: Un-crashed--resetting damage & fires."); 
       reset_damage_fires ();
    } 
     
  });
  
  #whenever the main aircraft's damage level, fire or smoke levels are updated,
  # broadcast the updated damage level via MP, but with a delay
  # (delay is because the mp_broadcast system seems to get overwhelmed)
  # when a lot of firing is going on)
  #         
  setlistener("/bombable/attributes/damage", func {
    
    settimer (func {mp_send_main_aircraft_damage_update (0)}, 4.36);
     
  });
  setlistener("/bombable/fire-particles/fire-burning", func {
    
    settimer (func {mp_send_main_aircraft_damage_update (0)}, 3.53);
     
  });
  setlistener("/bombable/fire-particles/damagedengine-burning", func {
    
    settimer (func {mp_send_main_aircraft_damage_update (0)}, 4.554);
     
  });
  
  
  print ("Bombable (ver. "~ bombableVersion ~") loaded - bombable, weapons, damage, fire, and explosion effects");

  #we save this for last because mp_broadcast doesn't exist for some people,
  # so runtime error & exit at this point for them.  
  
  props.globals.getNode(MP_broadcast_exists_pp, 1).setBoolValue(0);
    
  # is multiplayer enabled (overall for FG)?
  if ( getprop("/sim/multiplay/txhost") ) {
    Binary = mp_broadcast.Binary;
print("Bombable: Bombable successfully set up and enabled for multiplayer dogfighting (you can disable Multiplayer Bombable in the Bombable menu)");
    props.globals.getNode(MP_broadcast_exists_pp, 1).setBoolValue(1);
  }
  
  #broadcast = mp_broadcast.BroadcastChannel.new(msg_channel_mpp, parse_msg, 0);
  #if (broadcast==nil) print ("Bombable: Error, mp_broadcast was not set up correctly");
  #else { 
     
  #};
  #test_msg();

} 



#we do the setlistener to wait until various things in FG are initialized
# which the functions etc in bombableInit depend on.  Then we wait an additional 15 seconds

_setlistener("/sim/signals/nasal-dir-initialized", func {

    #settimer (func {bombableInit()} , 5);
    bombableInit();

});