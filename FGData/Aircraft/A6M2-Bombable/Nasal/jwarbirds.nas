#
# jwarbirds.nas - A common nas script for Japanese warbirds.
# Feb. 03, 2006: Tat Nishioka
# 
# Overview:
# JapaneseWarbirds class has a collection of property "observers", 
# which updates or overrides some FlightGear property.
# 
# Once this class is instanciated, its object will automatically register 
# timer. It, then, invoke "update" methods of all registered observers on 
# each timer event. When you add a new observer for a new gauge, write a 
# new observer class in your aircraft's nasal script (say ki-84.nas). 
# 
# Usage: 
# The following code in an aircraft specific nasal file (say ki-84.nas) let
# Ki-84 use three predefined observers.
# 
# var ki84 = JapaneseWarbirds.new();
# var observers = [Altimeter.new(), BoostGauge.new(), GForce.new()];
# foreach(observer; observers) { ki84.addObserver(observer)
# 
# Design Note:
# This script helps Japanese War-birds developers concentrate on making 
# aircraft specific observers since the common code and the aircraft specific
# code are separated. When you make a new aircraft, copy jwarbirds.nas 
# into its Nasal directory. Then write <aircraft_name>.nas file that contains 
# the instanciation of JapaneseWarbirds class and aircraft specific observers. 
# If you find several aircraft have the same observers, put these into 
# jwarbirds.nas. Do not put aircraft specific observers into jwarbird.nas
#

#
# Canopy class - this is not an observer 
#
Canopy = {
    new : func {
        var obj = { parents : [Canopy],
        canopy : aircraft.door.new("/controls/canopy", 2) };
        setlistener("/controls/canopy/opened", func(n) { obj.toggleOpenClose(n.getBoolValue()); }, 1);
        return obj;
    },

    toggleOpenClose : func(state) {
      me.canopy.move(state);
    }
};

#
# G-Force observer.
# This class updates the viewpoint of the pilot regarding the G-force.
#
GForce = {
    new : func {
    var obj = { parents : [GForce] };
    return obj;
    },

    update : func {
        force = getprop("/accelerations/pilot-g");
        if (force == nil) { force = 1.0; }
        eyepoint = getprop("sim/view/config/y-offset-m") + 0.01;
        eyepoint -= (force * 0.01);
        if (getprop("/sim/current-view/view-number") < 1) {
            setprop("/sim/current-view/y-offset-m", eyepoint);
        }
    }
};

#
# Altimeter observer - unit converter (ft to m) for altimeter.
#
Altimeter = {
    new : func {
        var obj = { parents : [Altimeter] };
        return obj;
    },

    update: func {
        setprop("/instrumentation/altimeter/indicated-altitude-m", getprop("/instrumentation/altimeter/indicated-altitude-ft") * 0.3048);
    }
};

#
# Cylinder temperature observer - simulates the cylinder temperature
#
CylinderTemperature = {
    new: func {
        var obj = { parents : [CylinderTemperature] };
        setprop("/engines/engine/cyl-temp", 0.0);
        return obj;
    },

    update: func {
        var cht_degf = getprop("/engines/engine/cht-degf");
        if (cht_degf != nil) {
          setprop("/engines/engine/cyl-temp", cht_degf / 2500);
        } else {
          if (getprop("/engines/engine/running") != 0) {
            interpolate("/engines/engine/cyl-temp", 0.5 + (getprop("/controls/engines/engine/throttle") * 0.5), 150);
          } else {
            interpolate("/engines/engine/cyl-temp", 0.0, 500);
          }
        }
    }
};

#
# BoostGause observer - unit converter from inHg to mmHg
#
BoostGauge = {
    new: func {
        var obj = { parents: [BoostGauge] };
        return obj;
    },

    update: func {
    # for both JSBSim and YASim version, this nil check is required since mp-osi is not set when fdm-initialized is set
    if ((var mp_osi = getprop("/engines/engine/mp-osi")) != nil) {
        interpolate("/engines/engine/boost-gauge-mmhg", mp_osi * 25.4 - 750.006168, 0.2);
        }
    }
};

#
# Exhaust Gas Temperature observer (EGT)
# This is mainly for YASim since it doesn't seem showing egt correctly.
# If you use JSBSim, then you might not need this unless engine parameters are wrong.
#
# displacement: displacement of the engine in SI (1 litre = 0.001 SI)

ExhaustGasTemperature = {
#
# new(displacement);
# displacement : displacement of the engine (Liter)
#
    new : func(displacement) {
        var obj = { parents : [ExhaustGasTemperature], 
        p_amb_sea_level : getprop("/environment/pressure-sea-level-inhg") * 3386.3886,
        displacement : displacement * 0.001 };
        setprop("/instrumentation/egt/egt-degc", getprop("/environment/temperature-degc"));
        return obj;
    },

  # approx. calculation of combustion efficiency
    get_combustion_efficiency : func {
        var combustion_efficiency = 0.0;
        var mixture = getprop("/controls/engines/engine/mixture");
        var thi_sea_level = 1.3 * mixture;
        var p_amb = getprop("/environment/pressure-inhg") * 3386.3886;   # ambient pressure (Pa)
        var equivalence_ratio = thi_sea_level * me.p_amb_sea_level / p_amb;

        if (equivalence_ratio < 0.9) {
            combustion_efficiency = 0.98
        } else {
        combustion_efficiency = 0.98 - (0.577 * (equivalence_ratio - 0.9));
        if (combustion_efficiency < 0.1) {
            combustion_efficiency = 0.1;
            }
        }
        return combustion_efficiency;
    },

    get_air_flow : func(t_amb) {
    var r_air = 287.3;
    var volumetric_efficiency = 0.8;
    var map = getprop("/engines/engine/mp-osi") * 6894.7573;       # manifold pressure (Pa)
    var rpm = getprop("/engines/engine/rpm");
    me.rpm = rpm;

    var v_dot_air = (me.displacement * rpm / 60) / 2 * volumetric_efficiency;   

    return v_dot_air * map / (r_air * t_amb);
    },

    update : func {
    #
    # This function is almost the same as doEGT() in JSBSim
    # except this uses some approx. calculations
        var cp_air=1005;
        var cp_fuel=1700;
        var calorific_value_fuel = 47300000;

        var t_amb = getprop("/environment/temperature-degc") + 273.15;   # ambient temp. (K)

        if (getprop("/engines/engine/running") == 1) {
            var combustion_efficiency = me.get_combustion_efficiency();
            var m_dot_air = me.get_air_flow(t_amb);
            var m_dot_fuel = m_dot_air / 14.7;
            var enthalpy_exhaust = m_dot_fuel * calorific_value_fuel * combustion_efficiency * 0.33;
            var heat_capacity_exhaust = (cp_air * m_dot_air) + (cp_fuel * m_dot_fuel);
            var delta_T_exhaust = enthalpy_exhaust / heat_capacity_exhaust;
            var egt = t_amb + delta_T_exhaust - 273.15;
            setprop("/instrumentation/egt/egt-degc", egt);

# Engine Power without mixture correction - just for test
     var dt = 1.0 / 120.0;
     var mp_inhg = getprop("/engines/engine/mp-osi") * 0.014138;
     var manxrpm = mp_inhg * me.rpm;
     var percentage_power = (0.000000006 * manxrpm * manxrpm) + (0.0008 * manxrpm) - 1.0 + ((288 - t_amb) * 7 * dt);
     if (percentage_power < 0) {
       percentage_power = 0.0;
     }
     setprop("/engines/engine/power", 950 * percentage_power);
# end test

        } else {
        # goes back to the ambient temperature in 1 min
        interpolate("/instrumentation/egt/egt-degc", t_amb - 273.15, 60);
        }
    }
};

#
# Automatic Mixture Controller
# This class automatically adjust the mixture value depending on
# current exhaust gas temperature (egt) and given target egt.
# In acutal aircraft, mixture is adjusted using air density but
# it is easier to adjust using current egt and target egt
# 
AutoMixtureControl = {
  #
  # new(target_egt_degc)
  # target_egt_degc : egt where engine can get maximum power (Celsius)
  #
  new : func(target_egt_degc) {
    var obj = {
       parents : [AutoMixtureControl],
       target_egt : target_egt_degc
    };
    setprop("/controls/engines/engine/manual-mixture-control", 0);
    return obj;
  },

  #
  # automatic mixture adjuster
  #
  update : func {
    if (getprop("/controls/engines/engine/manual-mixture-control") != 1 and 
        getprop("/engines/engine/running") == 1) {
      var mixture = getprop("/controls/engines/engine/mixture");
      var axis = getprop("/controls/engines/engine/mixture");
      var egt = getprop("/instrumentation/egt/egt-degc");
      var delta = me.target_egt - egt;
      delta = me.target_egt - egt;
      mixture -= (delta / 1000); 
      if (mixture > 1.0) {
        mixture = 1.0;
      } elsif (mixture < 0.0) {
        mixture = 0.0;
      }
      interpolate("/controls/engines/engine/mixture", mixture, 0.5);
    }
  }
}; 

#
# Japanese Warbird class - adds and updates observers
#
JapaneseWarbird = {
    new : func {
        var obj = { parents : [JapaneseWarbird],
        observers : [],
        canopy : Canopy.new() };
    setlistener("/sim/signals/fdm-initialized", func { obj.registerTimer(); });
    return obj;
    },

  #
  # addObserver(observer)
  # add an observer object to the JapaneseWarbird object
  # each observer must have a method named "update"
  # 
    addObserver : func(observer) {
        append(me.observers, observer);
    },

  # 
  # update()
  # update each observer in turn
  # 
    update : func {
        foreach (observer; me.observers) {
        observer.update();
        }
    me.registerTimer();
    },
  
  #
  # timer driven function
  #
    registerTimer : func {
        settimer(func { me.update() }, 0);
    }
}
