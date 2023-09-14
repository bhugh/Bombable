A-10 (YASim) readme.

This is not an authentic representation of an A-10 but it's based on
the right numbers, where I could find them.  There is a lot of
guesswork in the fdm.  It should also be noted that this a/c is still
very much under development, in nearly every respect and there are
several aspects which need fixing/improving.

History
-------
The Fairchild A-10 CAS (Close Air Support) aircraft is the production
version of the YA-10A, which was the winner in the U.S.A.A.F. A-X
fly-off, where it beat the Northrop YA-9A.

Model
-----
The model was originally constructed in Realsoft3D (linux beta V4.5),
exported as a .OBJ format file and imported into AC3D where it was
converted into .ac format and textured.

The accuracy of the model is heavily dependent on the data and
drawings available for it, and in most cases, the side, front and top
views in a typical 3-view drawing rarely align correctly or measure
consistently.  For example, when the model is scaled to the correct
length, the wing-span is likely to be a little out.


Flight Data Model
-----------------
The Flight Data Model uses the FlightGear YASim fdm solver, which
uses a combination of aircraft geometry and performance data to
generate the flight model.

Apart from the basic length, span and height of the aircraft, most of
the measurements needed for YASim are not generally available so
after uniformly scaling the 3d model to one of the basic measurements
i.e. length, the geometry data was taken from the model.

While this may not give the most accurate numbers, with respect
to the original aircraft, it does mean that what you fly matches
pretty closely to what you see, at least as far as the geometry
is concerned.

Information on the A-10s performance is fairly abundant but achieving
the full performance has proved difficult so the current fdm should
be regarded as developmental and still incorporating a lot of
guesswork.

While the low altitude performance seems more or less acceptable, it
cant reach it's sevice ceiling of 45,000ft and I have done little
testing of the single engine loiter/cruise modes.

The approach parameters have required even more guesswork.  They
are based upon a few photographs I was able to find showing the
aircraft in what appeared to be the final approach stages, and 
whatever info I was able to find.

Keyboard mapping
----------------
The following additional/non-standard keyboard mappings are set up
for this aircraft

Key               Action
'd'               Retract slats
'e'               Fire GAU-8/A cannon
'f'               Extend slats
'K' (Shift-k)     Toggle trajactory markers on & off

3D Panel
--------

Altimeter:
Mouse clicking inGH adjustable.

Lighting of the panel and instruments:
Look for the extrem bottom of the right console, there is one
of the several lighting sub-panel of the A-10. Curently Ctrl-C
key doesn't show correctly the hot spots, but, 'FLY INST' works
and adjusts the instruments lighting. 'CONSOLE' works too and 
adjusts the instruments mount's lighting.

Radio and navigation system:
See README.nav-system - FIXME -

Fuel gauges:
The fuel gauges panel at the bottom right of the main panel as a
combined display. The two needles display the internal amount of
fuel, left needle is left internal fuselage tank plus left
internal wing tank, same for the right side. the digital counter
displays the total of both side's internal tanks plus (if needed)
the total of the three external tanks.  - FIXME -








2D Panels (outdated)
--------------------
Currently, there are two simple 2D panels for the model, neither
of which are in any way accurate - they are simply holders for
the instruments.  The 'vfr' panel includes the basic instruments
needed for 'vfr' and calls the 'standard' FlightGear instruments
from the FlightGear installation.  The 'mini' panel includes a
subset of the instruments on the 'vfr' panel, with a transparent
background.

In addition to the standard FG instruments, both panels also
incorporate a number of custom instruments.  These are mostly
informational but two of them can be used to control some of the
Autopilot functions - see below.

Custom Controller Instruments
-----------------------------
There are two custom instruments on both the 'vfr' and 'mini'
panels that can be used to control some of the autopilot
functions.  These are the speed controller and the altitude mode
controller.

AP Speed Controller
-------------------
The speed controller can be used to hold the aircraft speed by
throttle, either to a set KIAS, or to a set mach value.
Clicking with the mouse on the yellow 'K' will set the AP speed
controller into KIAS hold, while clicking on the blue 'M' will
set Mach hold.  The numeric value displayed in either yellow or
blue indicates the set speed, in either kias or mach,
relatively.  There is a small array of '+' and '-' characters to
the left of the instrument and these can be used to increment or
decrement the speed setting, in either 10kt or 1kt steps for
kias or 0.1 and 0.01 steps for mach.

AP Altitude Mode Controller
---------------------------
The altitude mode controller appears as a strip reading

    AP Mode: AH TF TO IL MC

The meaning of the different modes are:

	AH = Altitude Hold
	TF = Terrain Following
	TO = Automatic Take-Off
	IL = Automatic Instrument Landing
	MC = Mach Climb

AH Mode
-------
The AH (Altitude Hold) function is intended to hold the aircraft
at the altitude set in /autopilot/settings/target-altitude-ft.
When engaged, the set altitude can be changed by using the
standard FG keystrokes.

TF Mode
-------
The TF (Terrain Following) function is intended to hold the
aircraft at a constant distance above ground level (agl).  The
separation distance is set in /autopilot/settings/target-agl-ft.
It is not currently possible to change this setting from either
of the panels - it must be changed via the property browser.

It should also be noted that FG does not currently provide a
look-ahead function that could be used for a proper terrain
following system so the current terrain following function works
by simply checking the agl directly below the a/c.  This means
that the TF function can only react after the separation has
increased or decreased and will not stop you from flying into
steep sided ground elevations i.e. cliffs.

TO Mode
-------
The TO (automatic take-off mode) function is intended to be used
to automate the take-off process.  It should be noted that the
a/c has the parking-brake engaged when FG starts and this should
be released before trying to take-off.  When TO mode is engaged,
the following sequence of actions take occur:

  The current heading of the a/c on the runway is set for both
  the ground-roll and in-air heading.
  
  The flaps are extended to 0.64
  
  Hold speed-with-throttle is engaged (KIAS mode)
  
  The wing-leveller is engaged
  
  Rudder/nose wheel steering is engaged.

As soon as speed-with-throttle is engaged, the a/c will start
accelerating down the runway and once it has sufficient speed it
will rotate and lift off from the ground.  Note that during the
ground roll there is no specific means of keeping the a/c on the
runway centre-line so while the a/c will hold the heading, there
may be some drift across the runway in cross-winds.

Once the a/c has climbed above 50ft agl, a climb-out pitch-hold
controller is engaged, to hold the a/c at a constant pitch, the
under-carriage is retracted, the rudder control is reset and the
rudder re-centred.

As the aircraft continues accelerating, the flaps are
progressively retracted until the a/c exceeds 180 kias.  Once
this speed has been exceeded the heading hold is switched to
true-heading-hold, the flap retraction is completed, speed
control is set to mach-with-throttle and Mach-Climb mode (see
below) is engaged.  The final action is to disable the AP TO
mode so that it cannot be engaged in flight.

It is possible to set a number of way points before engaging the
TO function but it is then necessary to hit Ctrl-h a couple of
times to dis-engage true-heading-hold, which is set whenever a
way point is entered, and re-centre the ailerons before TO is
engaged.  What will happen in this case is that once the
take-off sequence has finished and true-heading-hold is engaged,
the a/c will turn to the appropriate heading and follow the way
points.  If no way points have been set the take-off heading
will be followed.

IL Mode
-------
The IL (automatic instrument landing) function is designed to
land the aircraft automatically, provided that the runway you
wish to land on has an instrument landing system.  It is assumed
that the radio nav equipment will have already been correctly
tuned for the intended landing runway.

When engaged, the IL function will set nav1-heading-hold, set a
target speed of 270kt and either climb or descend to get on to
the glide-slope.

Once a vertical descent rate of > 15 fps is exceeded the target
speed for the AP speed controller is set to 150kt and the
'speed-brakes' are deployed (1.0).  As the speed drops the flaps
are progressively deployed, the 'speed brakes' are progressively
reduced and the undercarriage is extended.

Once the ias drops below 155kt an AoA-hold-by-throttle
controller is engaged and this will gradually reduce speed until
an approach AoA of 9 degrees is achieved.

Once the a/c drops below 50ft agl the AP controller switches
to touch-down mode and will try to set the a/c down at around
0.1 vfps (currently it's between 2-3 vfps).

Note: When the aircraft drops below 200ft agl the heading hold 
lock is disabled so any final corrections are up to you.

MC Mode
-------
The MC (Mach Climb Mode) function is designed to command the
highest climb rate that can be sustained for a given mach
setting and is only enabled when mach-hold-by-throttle is
selected on the AP Speed Controller.  This function has some
limitations, one being that it works best when the aircraft is
travelling below the set mach number and is accelerating.  If
the aircraft is already travelling at the set mach number the
climb rate is likely to be very low and it may be necessary to
temporarily reduce speed, and then increase it again (using the
AP Speed Controller) or force a climb by pulling back on the
stick.


Lee Elliott.     2004/11/14
