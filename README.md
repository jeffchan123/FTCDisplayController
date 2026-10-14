This project creates a centralized controller for FTC tournaments.  This can be adapted to any type of remotely managed (mirrored and interactive) display using cheap hardware ( e.g. Firesticks )

# Features
- Monitor and manage seven Fire TV Sticks from one local browser dashboard.
- Support E9L29Y, K2R2TE, and M3N6RA models with model-specific toolbar-hiding sequences.
- Configure the scoring server, event code, and display type: Audience, Field, Pit, Sponsor, or Championship Bar.
- Choose monitor-only startup or automatically set up assigned displays.
- View screen previews with Realtime, 2-second, 5-second, or 10-second refresh options.
- Show connection status, preview age, stale-preview warnings, and activity logs.
- Automatically reconnect offline devices, with optional restoration of their assigned display.
- Assign location names to devices and include them in scrcpy window titles.
- Select devices for group setup, reconnect, recovery, and scrcpy actions.
- Minimize unused device cards and automatically reflow the dashboard.
- Recover displays by reopening their saved URL and rerunning the toolbar-hiding sequence.
- Send remote commands: Wake, Home, Back, Menu, directional arrows, and OK.
- Open scrcpy for live viewing and control at 800-pixel maximum size, 15 FPS, and 1 Mbps.
- Apply and verify screensaver and sleep settings during display setup.
- Save device names, assignments, selections, minimized states, and connection preferences across restarts.
- Run locally on macOS using Python 3, ADB, and scrcpy, with no additional Python packages required.

# Hardware
- Firestick models supported: E9L29Y, K2R2TE, M3N6RA.  Other models may be supported, but have not been tested.  The main requirements are ABD controllability and whether the built-in web browser ( called Silk ) supports full screening through sent keystrokes.  The older firestick 4k models seem to work better.
- Any mac that runs python3 and srccpy.  My current setup is 2010 Macbook Pro High Sierra (10.13.6) running an older version of scrcpy.

# How to run
- On a mac, open the .command file, that will open a terminal window and then a web page to the application.
- You can create an alias to the .command file and put on the desktop for easy access

# Screenshot
<img width="1392" height="818" alt="Screen Shot 2026-10-14 at 10 46 49 AM" src="https://github.com/user-attachments/assets/c73cc3e4-5dc8-4c76-bea9-256512f3dc1c" />

# Walkthrough Video
- https://youtu.be/2tGv_L5cdYM

# Tips
- If using for the field display and game sounds, use an ethernet adapter over wifi.  Wifi has about 1/2 second latency for the sound.

# Next steps
- Review the Install-Guide and User-Guide

# Known issues
- Firesticks come in many different versions, some of which will not allow ADB management.
- Firesticks are a consumer product, Amazon sends all sorts of popups, test the config prior to an event
