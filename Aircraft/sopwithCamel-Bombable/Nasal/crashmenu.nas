###############################################################################
## Dialogue pop-up on A/C crash, giving various options
## Based on the WildFire configuration dialog,
## which is partly based on Till Bush's multiplayer dialog
## to start, do dialog.init(30,30, "Menu Title"); dialog.create("menu title");

var CONFIG_DLG = 0;

var dialog = {
#################################################################
    init : func (x = nil, y = nil, ttl=nil) {
        me.x = x;
        me.y = y;
        me.bg = [0, 0, 0, 0.3];    # background color
        me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
        #
        # "private"
	if (ttl==nil)   me.title = "Crash";
	else me.title=ttl;
        me.basenode = props.globals.getNode("/sim/menu/camel-crash");
        me.dialog = nil;
        me.namenode = props.Node.new({"dialog-name" : me.title });
        me.listeners = [];
    },
#################################################################
    create : func ( ttl="Crash!")  {
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
        titlebar.addChild("text").set("label", ttl);
        var w = titlebar.addChild("button");
        w.set("pref-width", 16);
        w.set("pref-height", 16);
        w.set("legend", "");
        w.set("default", 0);
        w.set("key", "esc");
        w.setBinding("nasal", "camel.dialog.destroy(); ");
        w.setBinding("dialog-close");
        me.dialog.addChild("hrule");

        var buttonBar1 = me.dialog.addChild("group");
        buttonBar1.set("layout", "hbox");
        buttonBar1.set("default-padding", 10);
     
        lreset = buttonBar1.addChild("button");
        lreset.set("legend", "Reset");
        lreset.set("equal", 1);                
        lreset.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lreset.prop().getNode("binding[0]/script", 1).setValue("camel.crashReset();");
        lreset.prop().getNode("binding[1]/command", 1).setValue("dialog-apply");
        lreset.prop().getNode("binding[2]/command", 1).setValue("dialog-close");        

        lcont = buttonBar1.addChild("button");
        lcont.set("legend", "Continue");
        lcont.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lcont.prop().getNode("binding[0]/script", 1).setValue("camel.crashContinue();");
        lcont.prop().getNode("binding[1]/command", 1).setValue("dialog-apply");
        lcont.prop().getNode("binding[2]/command", 1).setValue("dialog-close");        

        me.dialog.addChild("hrule");

        var buttonBar2 = me.dialog.addChild("group");
        buttonBar2.set("layout", "hbox");
        buttonBar2.set("default-padding", 10);

		lraise100 = buttonBar2.addChild("button");
        lraise100.set("legend", "Raise 250 ft/Continue");
        lraise100.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lraise100.prop().getNode("binding[0]/script", 1).setValue("camel.crashRaise(250);");
        lraise100.prop().getNode("binding[1]/command", 1).setValue("dialog-apply");
        lraise100.prop().getNode("binding[2]/command", 1).setValue("dialog-close");        

        lraise1000 = buttonBar2.addChild("button");
        lraise1000.set("legend", "Raise 1000 ft/Continue");
        lraise1000.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lraise1000.prop().getNode("binding[0]/script", 1).setValue("camel.crashRaise(1000);");
        lraise1000.prop().getNode("binding[1]/command", 1).setValue("dialog-apply");
        lraise1000.prop().getNode("binding[2]/command", 1).setValue("dialog-close");        

        lraise5000 = buttonBar2.addChild("button");
        lraise5000.set("legend", "Raise 5000 ft/Continue");
        lraise5000.prop().getNode("binding[0]/command", 1).setValue("nasal");
        lraise5000.prop().getNode("binding[0]/script", 1).setValue("camel.crashRaise(5000);");
        lraise5000.prop().getNode("binding[1]/command", 1).setValue("dialog-apply");
        lraise5000.prop().getNode("binding[2]/command", 1).setValue("dialog-close");        


        
        me.dialog.addChild("hrule");

        var buttonBar3 = me.dialog.addChild("group");
        buttonBar3.set("layout", "hbox");
        buttonBar3.set("default-padding", 10);

        lcancel = buttonBar3.addChild("button");
        lcancel.set("legend", "Cancel");
        lcancel.set("equal", 1);
        lcancel.prop().getNode("binding[0]/command", 1).setValue("dialog-close");

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


var crashReset = func {

  crashContinue();
  fgcommand ("reinit");

}

var crashContinue = func {

    #unfreeze/pause/crash
    setprop ("/sim/freeze/clock", 0);
    setprop ("/sim/freeze/master", 0);
    setprop ("/sim/crashed",0); #we set this in jsbsim.nas, now we unset it
    
    #view.stepView(-1,1); #@ crash we kicked them out of the A/C (in JSBSim.nas), now we put them back in
    setprop("/sim/current-view/view-number", 0);

}

var crashRaise = func (distance_ft=100) {

 var elevprop="/position/altitude-ft";
 setprop (elevprop, distance_ft + getprop(elevprop));
 crashContinue();

}
