BOMBABLE: FLIGHTGEAR BOMBING RANGE, DOGFIGHTING, AND TANK SCENARIOS, ver 4.5b
(for FlightGear ver 1.9.0, 1.9.1, 2.0, 2.4.0, 2.6.0, 2.8.0, 2.10.0, 2.12.x)

Brent Hugh, brent@brenthugh.com
Available at http://brenthugh.com/flightgear/bombable4-5b.zip

SHORT INSTRUCTIONS:

What it is:
 
  * With this distribution you can BOMB THINGS and DOGFIGHT in AI 
  scenarios in FlightGear.
  
  * Your aircraft receives damage from weapons or when you crash; y
  you can shoot and bomb scenery, buildings, bridges--basically anything
  in the FlightGear world. 
  
  * You can also do multiplayer dogfighting using Sopwith Camel (YASim) - Bombable ,
  SPAD VII - Bombable, Fokker DR 1 Triplane (JSB) - Bombable, A6M2 (Zero) - Bombable, 
  F6F Hellcat - Bombable, A10-Bombable, and ufo-bombable.

  (Note: Multiplayer dogfighting is possible with the planes 
  listed ONLY.  Look for the planes with suffix -Bombable. 
  However, all other features of Bombable will work 
  automatically with almost all existing FlightGear aircraft. The main 
  requirement is an aircraft that can shoot some kind of weapon or drop 
  a bomb--which many can.)

Bombable 4.5 works with Flightgear 2.0.0 and above, including 2.10.0. 

Improvement: As of version 4.4, Bombable no longer overwrites any 
existing files or aircraft in the standard FlightGear installation. 
It adds new aircraft, AI aircraft, and scenarios but does not change any 
currently installed aircraft. It will overwrite files from any 
previous Bombable installation but will not change any other files.

Uninstalling: Bombable is easy to disable-uninstall. You **do not** need 
to wipe out & reinstall your FlightGear installation to remove Bombable.
Just delete the file data/Nasal/bombable.nas and bombable will be removed 
from your installation.  

See file bombable-uninstall.txt for more info. 

See the file bombable-whatsnew.txt for more details about what is new 
in this release.

How to use:

  * Unzip to FG/data - preserve directory structure if your unzip 
  utility gives you the choice. This will add files to four 
  directories under FG/data (AI, Aircraft, Nasal, Docs). Unzip these 
  files on top of your current installation; this will add some new 
  files and replace any files installed by a previous version of 
  Bombable.
  
  * AI: Choose a scenario. All scenarios have detailed 
  instructions--you will NEED to read them.
  
  * MOVE SCENARIOS TO YOUR LOCATION--WHEREVER THAT MAY BE: As of Version 
  4.4, Bombable will move scenarios to your location--whereever in 
  the world that may be!  You can re-spawn enemy aircraft, tanks,
  ships, etc. from ANY scenario to ANY location.  Simply load the scenario you
  want, go to the location you want, and when you are ready to engage, select 
  in the FG menu Bombable/Bombable Options and then "Respawn AI Aircraft" and/or
  "Respawn AI Ground/Water Craft".  This will move any aircraft, ships, tanks,
  jeeps, etc from the scenario to your immediate location, where you can find
  and engage them.   
  
  * MP: Get a partner to also load this package, both choose Sopwith 
  Camel (YASim--easier--or JSBSim--more historically accurate), both 
  turn on multiplayer, both go to same location, 
  and dogfight each other. You will be able to see the damage you are 
  doing to the other person and status messages will appear with your 
  own damage level. You may catch on fire or blow up, depending on how 
  good the other pilot is . . .
  
  (You can use the Sopwith Camel-Bombable (YASim or JSBSim) or a few 
  other aircraft for dogfighting--see separate 
  bombable-multiplayer-dogfighting.txt for more detailed instructions.)
  
  * Once you have started FlightGear, note the "Bombable" options menu.  
  The defaults are set to very easy because that is least frustrating for 
  beginners.  If you want to try the harder/more realistic options--go ahead! 
  Key options are "Weapon realism",  "AI Weapon effectiveness", and "AI 
  aircraft flying/dogfighting skill".  
  
  * In MP mode, all players should use the same "Weapon realism" 
  settings or it won't be fair.
  
  * Best aircraft: A-10-Bombable (for bombing runs); Sopwith Camel-Bombable 
  (YASim or JSBSim), F6F Hellcat-Bombable, or A6M2-Bombable (Zero) for dogfights.  
  Of the WWI-era aircraft, SPAD-VII-Bombable is smoothest & easiest to 
  aim weapons, Sopwith Camel-Bombable (YASim) is slightly more difficult, and 
  Sopwith Camel-Bombable (JSBSim) is far more difficult to control but also very
  historically accurate.
  
  * To see smoke & fire effects (contrails, smoke, etc), which are a 
  very important part of this package, you must have Particles enabled 
  in View/Rendering Options
  
  * Suggestion: If playing AI scenarios, disable multiplayer (many of 
  the scenarios are in the area of San Francisco where many 
  multiplayer aircraft are typically present--and MP aircraft can 
  dramatically slow your framerate).
 
When you install this package, be aware that it overwrites any 
previous version of the Bombable package you have installed.

It will **not** overwrite any other standard FG files or aircraft.

LONG DETAILED INSTRUCTIONS WITH THE ANSWERS TO ALL OF YOUR QUESTIONS

This package includes:

  - Bombable, damagable, shootable AI aircraft, ships, tanks, and 
  jeeps, including the A-10 "Warthog", Sopwith Camel, SPAD VII, and 
  Fokker DR 1 Triplane and others (look for suffix -Bombable in the FGRun
  menu) for your dogfighting pleasure.
  
  - AI aircraft will catch fire, explode, crash, sink, etc, as 
  appropriate when you have damaged them sufficiently. They will also 
  work to evade your attacks. They will also shoot at you and damage 
  your aircraft.
  
  - Flyable Sopwith Camel aircraft modded for dogfighting (use the 
  "YASim" version, easier, or JSBSim, more difficult), as 
  well as SPAD VII, Fokker DR 1 Triplane, and A6M2 Zero that have 
  working, historically accurate weapons AND that work for multiplayer 
  dogfighting.
  
  - Dogfighting that works with AI aircraft in scenarios OR over 
  multiplayer.
  
  - A large number of scenarios that put you in situations to use all 
  these ingredients--dogfighting, bombing, strafing, etc.
 
  - In multiplayer you can see the damage you are inflicting on the 
  other person and also the damage the other person is inflicting on 
  you. Although you can't see bombs or tracers from the other person 
  (due to current FG restrictions) you get continuous damage reports 
  and altogether it works pretty well.
  
  - When your damage gets to 100% in multiplayer mode or AI mode there 
  is a large explosion and your engine switches off. It doesn't go any 
  further than that--by making you crash or anything. It basically 
  just notifies you, "You just lost!" You can then have two options:
    1. Bombable menu/Bombable Options/Reset Main Aircraft Damage.  Then 
    re-start your engines (you may need to turn on your magnetos) and proceed.
    2. Do file/reset or reset your location ("Location" menu).  This will also
    to reset your damage level to zero.
     
  - When you crash in FlightGear you don't just wap into the 
  ground--now you explode, catch fire, engines shut down, etc., and 
  your damage is set to 100%. When you reset your position, damage is 
  set back to 0%.

 
INSTALLATION

Simply unzip this file into your FlightGear DATA directory and it 
will put all the files into their proper subdirectories.

Under Windows this directory is usually:

  c:/Program Files/FlightGear/data  

Answer "yes" if it asks you if you want to replace existing files. 
Answer "yes" if it gives you the option to preserve directory 
structure.

Unzip the new files **on top of** your existing FG installation 
files--that is, add them to your existing files. **Do not** remove 
the existing AI, Aircraft, Nasal, and Docs directories and replace 
them with the similar directories from Bombable. Bombable (and FG!) 
need all the existing FG files in those directories to work. 
Bombable only adds a few new files to them.

Again, be aware that this release will overwrite certain of your 
existing files:

 - It overwrites any previous version of this package you have installed
 - It does NOT overwrite or delete any existing FlightGear files.
 

HOW TO USE - MULTIPLAYER 

  * If you are playing multiplayer dogfights, simply select the 
  aircraft you want to use (Sopwith Camel-Bombable, SPAD VII-Bombable, 
  or FKDR1-Bombable YASim, A6M2 Zero-Bombable, A10-Bombable, ufo-Bombable), 
  select the location you are meeting your multiplayer dogfighting partners, 
  and start FlightGear.
  
  * The system doesn't actually take any action on your aircraft such 
  as disabling engines or controls (with one exception--see below). It 
  simply informs you of hits and damage levels. You and your MP 
  partners can decide any other rules you like.
  
  * When you reach 100% damage, your engine switches off and there is 
  a large explosion. You won't be able to turn your engines on 
  again--until you can choose file/reset to set your damage level back 
  to 0% OR select Bombable/Bombable Options/Reset Main Aircraft Damage.
  
  * Sopwith Camels and Fokker Triplanes are loaded with belts of 400 
  rounds in each of the machine guns. It is easy to use all that ammo 
  in a short time. To re-load, these aircraft requires you to land and 
  completely stop the engines (Zero RPM). Since the aircraft tend to 
  get bogged down on soft ground, it is best to land on an actual 
  runway. So--land on a runway, stop, engines off, 0 RPM, reload (in 
  the Camel or Fokker DR 1 menu), take off--you're back in action! And,
  of course, a sitting duck target all the time you are landing and 
  re-loading--but that's definitely realistic!

  * A6M2 Zero likewise has limited ammo--500 rounds of machine gun 
  ammo for each of two guns, and 60 rounds of cannon ammo. Fire 
  machine gun with 'e' and cannon with 'E'. (Triggers are 
  /controls/armament/trigger and /controls/armament/trigger1 for those 
  of you programming joysticks.)


HOW TO USE - AI SCENARIOS

  * If you start FlightGear via the FlightGear Wizard (FGRUN): In the 
  FlightGear Wizard, you will find the various scenarios listed under 
  "Scenarios". Simply select one of them and start FlightGear.
  
  * If you start FlightGear via command line, add an option similar to 
  this:

    --ai-scenario=Kansas_City_East_Bottoms_Bombing_Range

  * You will also need to choose an appropriate aircraft that is able 
  to shoot guns and/or drop bombs.
  
  * You will need to start at the suggested airport and locate the 
  targets. Instructions for locating the targets are in each AI 
  scenario. You can read the AI scenario file directly using a text 
  editor (scenarios are located in directory FG/data/AI by default) or 
  mouse over the scenario in the FG Wizard and the scenario 
  description will show.
  
  * All targets in scenarios have flares that leave tall smoke 
  columns (ground targets) or contrails/smoke trails (aircraft). This 
  makes them far easier to locate visually.
  
  * For greater realism, use the "Bombable" menu item to turn off the 
  smoke trails & flares. It is very, very challenging (yet entirely 
  realistic . . . ) to locate moving aircraft, tanks, and jeeps 
  visually in FlightGear without the telltale smoke trails.
  
  * Each scenario's has a description attached which tells 
  which airport to start at and how to locate the targets, and other 
  vitally important details you will need to know to use the scenario 
  successfully.
  
  * You should be able to read the scenario descriptions from within 
  the FlightGear Wizard--select the scenario, then click the blue 
  "question mark" button.
  
  * Or you can simply open the scenario files (XML files in 
  FG/data/AI). They are ordinary text files and you can open them with 
  any text editor and the description with instructions is right at 
  the top of the file.
  
  * To see the smoke and fire when you bomb or damage your targets 
  sufficiently, you will need to have "Particles" enabled (found in 
  the FlightGear menus under "View/Rendering Options".
  
  * Several options should appear under the "Bombable" menu when you 
  start FlightGear. You can turn off all visual smoke trails and fires 
  if you like, enable or disable multi-player mode, and difficulty 
  and accuracy levels, etc.
  
  * I believe that the realism level with "Weapon Realism (your weapons)" 
  set to "Ultra-Realistic" is approximately correct. In real life it is 
  very, very difficult to accurately hit a target using a machine gun 
  or canon from a fast-moving, bouncing aircraft. Trying to get enough lead 
  into a target to actually to it serious harm is NOT an easy thing to 
  do. Normally to completely disable an aircraft or vehicle you have 
  to strike it multiple times with very great accuracy. And that is 
  not easy! Yet there is always the chance of a single, lucky shot 
  completely disabling an aircraft or vehicle--and that happens under 
  these scenarios as well. But normally it is a matter of putting a 
  decent amount of armament right on the target and (with Easy Modes 
  off) that is not necessarily very easy to do.
  
  * However for starters I definitely suggest selecting "Easier" or 
  "Dead Easy" mode in Bombable/Bombable Options/Weapon Realism, leaving smoke 
  trails & flares on (the default), and moving AI aircraft & weapon 
  effectiveness to low levels. Doing that will greatly 
  reduce the frustration levels in your first missions. As soon as you 
  become more proficient, gradually disable the easy modes for a more 
  realistic and challenging experience.

MULTIPLAYER DOGFIGHTING

  * Multiplayer mode is enabled by default so if you and another 
  bombable-enabled Sopwith Camel are in the same general area you can 
  just start dogfighting and it will just work. You can disable 
  multiplayer communication via the Bombable menu.
  
  * See the separate readme for more detailed instructions for 
  dogfighting over multiplayer.
  
  * Also the enclosed "Dicta Boelcke" for advice and instructions for 
  dogfighting from WWI-era aces. Those instructions and advice carry 
  over perfectly into the FG world!


SCENARIOS - LISTED FROM EASIEST TO HARDEST

Keep in mind that you can now MOVE ANY SCENARIO TO ANY LOCATION.

Simply select Bombable/Bombable Options and click the 'Respawn'
buttons to bring any scenario you have loaded to your current location.

About the scenarios:

Successfully flying the aircraft and hitting targets is quite 
difficult. Unlike other combat simulators, the aircraft, bombs, and 
bullets in FlightGear are realistic. That means you first need to 
learn how to handle your aircraft and operate its systems, and then 
practice bombing and shooting runs of varying degrees of difficulty.

The scenarios in this package in approximate order of difficulty, 
easiest to hardest:

San Francisco Bay Ferry Invasion - KSFO

- The ferries are very large, fairly slow-moving (~20 knots), and 
perfect for practicing dive bombing and/or strafing techniques. The 
ships are quite easy to hit but it takes quite a large number of 
hits to damage and sink them.

Marin County Sopwith Camel Invasions - Marin Ranch, CA35

- A large number of Sopwith Camels are flying directly over the 
airport. Engage and destroy as many as you can--if you can destroy 
any at all! For starters, choose the Sopwith Camel-Bombable YASim version 
as your aircraft, or the SPAD VII-Bombable. Later you can also use the 
Fokker FKDR1-Bombable or Sopwith Camel-Bombable (JSBSim)--which is far 
more historically accurate in its flight model, but also very difficult
and frustrating to operate.

Marin County Zero Invasions - Marin Ranch, CA35

- A number of A6M2 Zeros are flying directly over the airport. 
Engage and destroy as many as you can--if you can destroy any at 
all! Best choice for your aircraft is the A6M2 Zero-Bombable (non-JSBSim 
version) as your aircraft

The "Zoo" versions have numerous aircraft, all of which will follow 
you and swarm around you.

The "Simple" version have one two or three aircraft.

You use the "Bombable" menu to turn off the fighter attacks if you 
like--then the fighters will simply fly in a straight line and you 
can try to follow them and attack.

You can also select Easy Mode (or Super Easy Mode; or both together) 
to make the AI aircraft turn and twist less vigorously--and become 
*much* easier to shoot.

Lee's Summit Bombing Range - KLXS

- Static targets in a fairly flat area, all targets in obvious 
locations near each other. However, the M1 Abrams tanks are very 
small in comparison with the large ferries. EVen static tank 
installations can be challenging to locate and hit.

Kansas City East Bottoms Bombing Range - KMKC

- Static targets in a fairly flat area; a large number of targets, 
over a quite large area; some targets are quite easy to find but 
others are quite difficult; tracking targets for repeated bombing 
runs in a flat, featureless area can be quite challenging

Kansas City East Bottoms Tank Columns one - KMKC

- Moving targets, all grouped together, in a fairly flat area

Kansas City East Bottoms Tank Columns two - KMKC

- Slightly faster moving targets, all grouped together, in a fairly 
flat area

Kansas City East Bottoms Tank Circulators - KMKC

- Moving targets in a flat area, but individual movement, not in 
formation

Sun Valley Bombing Range - KSUN

- Static targets in mountain valley; mountains interfere with flight 
and preparation for bombing runs

Sun Valley Tank Invasion 1 - KSUN

- Moving targets in mountain valley

Sun Valley Tank Invasion 2 - KSUN

- Moving targets in mountainous area--quite challenging!

Sun Valley Tank & Jeep Invasion - KSUN

- Jeeps are much smaller than tanks, much harder to see, much harder 
to hit.

Columbia CA Tank Invasion 1 & 2 & Tank/Jeep Invasion - O22

- Moving targets, narrow valley & mountainous--very challenging!

Pine Mountain Lake CA Tank Invasion 1 & 2 & Tank/Jeep Invasion - E45

- Moving targets, even narrower valley with tanks right in the 
bottom--very, very challenging!

San Francisco Cessna Invasion - KSFO

- A fleet of moving Cessnas is quite difficult to locate and hit. 
The Cessnas are fairly slow-moving and can't take much damage, so 
they would make a good target for a number of FG aircraft with 
simple machine gun armament.

San Francisco Warthog Invasion 1 & 2 - KSFO

- Tracking the low-flying Warthogs through the bay, under the bridge,
 and through the mountains east of Oakland is quite challenging. 
Hitting a fast-moving A-10 with a canon is quite challenging--you'll 
soon discover why guided missiles were invented.

Marin County WW II Bombers with Cover - CA35

This features a squadron of six B-17 bombers with fighter cover far 
above them. If you take off from runway 4 of the Marin Ranch airport,
 climb straight ahead to 5000 feet you will meet the bomber squadron 
there.

How many of the bombers and fighters can you knock out with your 
limited supply of ammo?

Best aircraft is A6M2-Bombable (Zero).

All tank/jeep scenarios

All scenarios involving M1 Abrams tanks or Jeeps can be made harder 
by using the menu "M1 Abrams/Change livery color" to change the 
color to camouflage and/or by using the Bombable menu to turn the 
vehicles' flares off. The whole issue of finding and tracking small, 
camoflauged, moving ground targets is a very difficult one but also 
a very realistic one. In some of the scenarios it is very difficult 
indeed to keep track of moving targets that blend into the terrain 
very well when seen from a distance.

You can also use the Bombable menu to disable smoke trails & 
contrails for aircraft. Tracking and following the Sopwith Camels or 
A-10s through the mountains without smoke trails/contrails to guide 
is you is a pretty good visual challenge.

AIRCRAFT

Any aircraft that shoots guns or drops bombs can (at least in theory 
or if set up correctly) damage the targets. The Fairchild A-10 
Thunderbolt  is a great choice (A-10-Bombable version is included in the 
package) - See instructions at 

  http://wiki.flightgear.org/index.php/Fairchild_A-10

If you are using the A-10 Thunderbolt, carefully read the FlightGear 
wiki page explaining how to operate the aircraft, use the bomb sight,
etc.

The F16 (3D cockpit version) seems to work well also, though it 
lacks bombs.

SPAD VII-Bombable  and Fokker DR 1-Bombable Triplane (versions 
included with this package that include working guns) work well to 
dogfight the AI Sopwith Camels.

A6M2 Zero, included with this package, is excellent for dogfighting, 
AI scenerios, and general flying.

Can gun/bomb impacts be detected for all aircraft?

FG allows aircraft designers wide latitude in choosing the internal 
variable that monitors the "impacts" of their armament are detected. 
The bombable system checks all the most common ways of reporting 
armament impacts and should work with all aircraft with armament set 
up to report impacts in the FG CVS version as of August 2009.

Beware there were a lot of conditions mentioned in that paragraph! 
Not all aircraft have armament and not all armament is set up to 
report impacts. In addition, a lot of the aircrafts' armament is 
fairly weak--you're going to have to hit an M1 Tank, or a 3500 tonne 
oceangoing ferry, with a WHOLE LOT of the light machine gun bullets 
from the F-16's standard machine gun, for instance, before there is 
any noticeable effect. On the other hand, that machine gun could 
easily take out a Cessna or a jeep.

However these scenarios, in theory, should work with these aircraft 
in the current FG CVS (as of August 2009):

A-10 Arsenal VG-33 B-1B BF109 BO105 F4U F-16 F-117 FW190 Horten-O 
Hunter IL-2 LA-5 ME-262 ME-262 HGIII Seahawk Sopwith Camel SPAD VII 
Spitfire Submarine Scout Vulcan 2B

Note that not all of these have actual weapons--some may have 
something like a drop-tank that is ballistic and can impact other 
objects. Again, you'll have to hit the M-1 with a lot of drop tanks 
before you disable it, so such an aircraft may not be your best 
choice . . .

The scenarios will likely work with many other aircraft/armaments, 
particularly if those aircraft use the standard impact report 
mechanism in FlightGear.

MODDING AIRCRAFT AND SCENERY OBJECTS TO BECOME BOMBABLE

If you are an aircraft designer and would like to make your aircraft 
bombable, see separate file 
"bombable-modding-aircraft-for-dogfighting.txt" for details.

FILES INCLUDED

Included files go in several places--as indicated in the directory 
structure of the zip file. If your FG is set up in a normal 
configuration you should be able to simply unzip the file in your 
top-level FlightGear directory and everything will end up where it 
belongs.

However if you prefer to do it by hand, here are the details:

1. SCENARIOS TO FG/data/AI:

The XML files in the top-level directory are AI scenarios. Copy them 
to the FlightGear/data/AI directory (exact name will vary according 
to your operating system and installation options).

2. AI Aircraft files to FG/data/AI/Aircraft:

Copy the entire Fire-Particles directory to the 
FlightGear/data/AI/Aircraft. Do the same with all the aircraft 
directories in the zip file under dad/AI/Aircraft, including 
M1-Abrams, jeep-bombable, ferry-bombable, c172-bombable, 
A-10-bombable, etc.

3. Regular aircraft (non-AI) to FG/data/Aircraft

Copy the entire sopwithCamel-guns directory to FG/data/Aircraft. If 
you currently have a sopwithCamel directory this will overwrite it.

4. bombable.nas to FG/data/Nasal

Copy the files "bombable.nas" and "mp_broadcast.nas" to 
FG/data/Nasal.

mp_broadcast.nas is now (9/2009) distributed with the CVS version so 
if you have that file already you can skip that step.

KNOWN ISSUES

See the to-do file enclosed with the distribution for a list of 
current issues.


CREDITS
The M-1 Abrams tank was created by Emmanuel BARANGER - David 
BASTIEN. The version included here has been fairly heavily modded to 
allow tank movement, change of livery, etc. If you have installed 
the Baranger/Bastien version of the M-1 Abrams you can simply remove 
those files and replace them with this modded version, which is 
fully backwards compatible.

See the original M-1 Abrams and a bombing scenario for it here:

http://croo.murgl.org/fgfs/AG-demo/index.html

This demo has the idea and all of the basic techniques that have 
been carried out more extensively and systematically in the Bombable 
package.

Sopwith Camel, SPAD VII, Fokker DR 1, and A6M2 (Zero) aircraft were 
all created by other people as acknowledged in the author lines in 
those files. The only contribution in this package was to add or 
modify guns so they work properly and/or create AI versions of the 
aircraft with the bombable modifications added. For the Sopwith Camel,
I also created a historically accurate flight model for the JSBSim
version.

Bombing scenarios in the package, creation of the "bombable.nas" 
resource file (modified from the original M1 Abrams tank nasal 
scripts and others), modding of the Fire-Particles objects (based on 
Fire-Particles submodels in the M1 Abrams tank), and modding of 
other AI aircraft to make them bombable and add other features, is 
by Brent Hugh. brent@brenthugh.com


LICENSE & DISTRIBUTION

Many/most aircraft and miscellaneous files that are included here 
are from a FlightGear distribution or CVS version, and so licensed 
under the GNU General Public License. See the details

Any modifications to these files made by Brent Hugh and any files 
written or created by Brent Hugh (particularly bombable.nas, 
bombable documentation files, and modifications to aircraft files) 
are released under the GNU General Public License:

// Copyright (C) 2013  Brent Hugh - brent@brenthugh.com
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 2 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// General Public License for more details.