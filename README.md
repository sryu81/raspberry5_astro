# raspberry5_astro
raspberry 5 configuration for astrophotography



# Troubleshooting 
1. gpsd and time sync configuration issue
## what was the problem with gpsd ?

A mount system using CP210X chipset for serial communication can interfere with the gps dongle that uses the same chipset.
In my case gps dongle uses different chipset so didn't suffer such issue but encountered another issue on gpsd.

/lib/systemd/system

/lib/udev/rules.d/60-gpsd.rules - when device is detected, trigger the systemd to run gpsdctl@.service with paramters (/dev/ttyACM0)
gpsdctl@.service -- activate the gpsdctl and run gpsd, arguments and variables are defined at /etc/default/gpsd

gpsd.service -- activate gpsd with arguments 
gpsd.socket  -- TCP socket listening on 2947


## so how to fix it?
you just need to change the value of this DEVICES variable in the /etc/default/gpsd

```
# Devices gpsd should collect to at boot time.
# They need to be read/writeable, either by user gpsd or the group dialout.
#DEVICES="/dev/ttyACM0"           // before
DEVICES="/dev/serial/by-id/usb-u-blox_AG_-_www.u-blox.com_u-blox_7_-_GPS_GNSS_Receiver-if00" 

# Other options you want to pass to gpsd
GPSD_OPTIONS="-n"

# Automatically hot add/remove USB GPS devices via gpsdctl
USBAUTO="true"
```

then systemctl status gpsd output will be like :
```
● gpsd.service - GPS (Global Positioning System) Daemon
     Loaded: loaded (/lib/systemd/system/gpsd.service; enabled; preset: enabled)
     Active: active (running) since Fri 2025-09-05 22:37:25 PDT; 3s ago
TriggeredBy: ● gpsd.socket
    Process: 27484 ExecStart=/usr/sbin/gpsd $GPSD_OPTIONS $OPTIONS $DEVICES (code=exited, status=0/SUCCESS)
   Main PID: 27485 (gpsd)
      Tasks: 2 (limit: 4762)
        CPU: 25ms
     CGroup: /system.slice/gpsd.service
             └─27485 /usr/sbin/gpsd -n /dev/serial/by-id/usb-u-blox_AG_-_www.u-blox.com_u-blox_7_-_GPS_GNSS_Receiver-if00
```

# 
