#
# Bombable addon
#
# Started by Brent Hugh
# Started in 2009
#
# Converted to a FlightGear addon by
# Brendan Black, Feb 2021

var main = func( addon ) {
    var root = addon.basePath;
    var myAddonId  = addon.id;
    var mySettingsRootPath = "/addons/by-id/" ~ myAddonId;
    # setting root path to addon
    setprop("/sim/bombable/root_path", root);


    # load scripts
    foreach(var f; ['bombable.nas'] ) {
        io.load_nasal( root ~ "/Nasal/" ~ f, "bombable" );
    }
}
